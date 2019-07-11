CfhighlanderTemplate do
  Name 'ec2-fleet'
  Description "ec2-fleet - #{component_version}"

  Parameters do
    ComponentParam 'EnvironmentName', 'dev', isGlobal: true
    ComponentParam 'EnvironmentType', 'development', allowedValues: ['development','production'], isGlobal: true
    ComponentParam 'VPCId', type: 'AWS::EC2::VPC::Id'
    ComponentParam 'KeyName', '', type: 'AWS::EC2::KeyPair::KeyName'
    ComponentParam 'Ami', type: 'AWS::EC2::Image::Id'
    ComponentParam 'SubnetIds', type: 'List<AWS::EC2::Subnet::Id>'

    ComponentParam 'DefaultTargetCapacityType', 'spot', allowedValues: ['on-demand','spot']
    ComponentParam 'OnDemandTargetCapacity', 0
    ComponentParam 'SpotTargetCapacity', 1
    ComponentParam 'TotalTargetCapacity', 1
  end


end
