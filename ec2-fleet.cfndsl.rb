CloudFormation do

  Condition('KeyNameSet', FnNot(FnEquals(Ref('KeyName'), '')))

  fleet_tags = []
  fleet_tags.push({ Key: 'Name', Value: FnSub("${EnvironmentName}-#{component_name}") })
  fleet_tags.push({ Key: 'Environment', Value: Ref(:EnvironmentName) })
  fleet_tags.push({ Key: 'EnvironmentType', Value: Ref(:EnvironmentType) })
  fleet_tags.push(*tags.map {|k,v| {Key: k, Value: FnSub(v)}}).uniq { |h| h[:Key] } if defined? tags

  EC2_SecurityGroup(:SecurityGroupFleet) do
    VpcId Ref('VPCId')
    GroupDescription FnSub("${EnvironmentName}-#{component_name}")
    SecurityGroupEgress ([
      {
        CidrIp: "0.0.0.0/0",
        Description: "outbound all for ports",
        IpProtocol: -1,
      }
    ])
    Tags fleet_tags
  end
  
  security_groups.each do |sg|
    EC2_SecurityGroupIngress("SecurityGroupRule#{sg['name']}") do
      Description FnSub(sg['desc']) if sg.has_key? 'desc'
      IpProtocol (sg.has_key?('protocol') ? sg['protocol'] : 'tcp')
      FromPort sg['from']
      ToPort (sg.key?('to') ? sg['to'] : sg['from'])
      GroupId FnGetAtt("SecurityGroupFleet",'GroupId')
      SourceSecurityGroupId sg.key?('securty_group') ? FnSub(sg['source_securty_group_ip']) : FnGetAtt("SecurityGroupFleet",'GroupId') unless sg.has_key?('cidrip')
      CidrIp sg['cidrip'] if sg.has_key?('cidrip')
    end
  end if defined? security_groups


  policies = []
  iam_policies.each do |name,policy|
    policies << iam_policy_allow(name,policy['action'],policy['resource'] || '*')
  end if defined? iam_policies

  Role('Role') do
    AssumeRolePolicyDocument service_role_assume_policy('ec2')
    Path '/'
    Policies(policies)
  end

  InstanceProfile('InstanceProfile') do
    Path '/'
    Roles [Ref('Role')]
  end

  fleet_tags.push({ Key: 'Name', Value: FnSub("${EnvironmentName}-fleet-xx") })
  fleet_tags.push(*instance_tags.map {|k,v| {Key: k, Value: FnSub(v)}}) if defined? instance_tags

  # Setup userdata string
  instance_userdata = "#!/bin/bash\nset -o xtrace\n"
  instance_userdata << userdata if defined? userdata
  instance_userdata << efs_mount if enable_efs
  instance_userdata << cfnsignal if defined? cfnsignal

  template_data = {
      SecurityGroupIds: [ Ref(:SecurityGroupFleet) ],
      TagSpecifications: [
        { ResourceType: 'instance', Tags: fleet_tags },
        { ResourceType: 'volume', Tags: fleet_tags }
      ],
      UserData: FnBase64(FnSub(instance_userdata)),
      IamInstanceProfile: { Name: Ref(:InstanceProfile) },
      KeyName: FnIf('KeyNameSet', Ref('KeyName'), Ref('AWS::NoValue')),
      ImageId: Ref('Ami'),
      Monitoring: { Enabled: detailed_monitoring }
  }

  if defined? volumes
    template_data[:BlockDeviceMappings] = volumes
  end

  EC2_LaunchTemplate(:LaunchTemplate) {
    LaunchTemplateData(template_data)
  }

  fleet_overrides = []
  overrides.each do |ovr|
    maximum_availability_zones.times do |az|
      obj = {}
      obj[:InstanceType] = ovr['type']
      obj[:MaxPrice] = ovr['price'] if ovr.has_key?('price')
      obj[:Priority] = ovr['priority'] if ovr.has_key?('priority')
      obj[:SubnetId] = FnSelect(az, Ref('SubnetIds'))
      obj[:WeightedCapacity] = ovr['weight'] if ovr.has_key?('weight')
      fleet_overrides << obj
    end
  end

  EC2_EC2Fleet(:Fleet) {
    ExcessCapacityTerminationPolicy (terminate_excess ? 'termination' : 'no-termination')
    LaunchTemplateConfigs([
      {
        LaunchTemplateSpecification: {
          LaunchTemplateId: Ref(:LaunchTemplate),
          Version: FnGetAtt(:LaunchTemplate, :LatestVersionNumber)
        },
        Overrides: fleet_overrides
      }
    ])
    OnDemandOptions({ AllocationStrategy: 'lowestPrice' }) #lowest-price | prioritized
    ReplaceUnhealthyInstances false
    SpotOptions({
      AllocationStrategy: 'lowestPrice', #diversified | lowestPrice
      InstanceInterruptionBehavior: 'terminate'
    })
    TagSpecifications([
      {
        ResourceType: 'fleet',
        Tags: fleet_tags.reverse.uniq { |h| h[:Key] }
      }
    ])
    TargetCapacitySpecification({
      DefaultTargetCapacityType: Ref(:DefaultTargetCapacityType),
      OnDemandTargetCapacity: Ref(:OnDemandTargetCapacity),
      SpotTargetCapacity: Ref(:SpotTargetCapacity),
      TotalTargetCapacity: Ref(:TotalTargetCapacity)
    })
    Type 'maintain'
  }
  
  Output(:SecurityGroupId) {
    Value FnGetAtt(:SecurityGroupFleet,:GroupId)
  }

end
