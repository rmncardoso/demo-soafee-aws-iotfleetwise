import os
import re
from aws_cdk import Stack, Duration, CfnOutput
from aws_cdk import aws_timestream as ts
from aws_cdk import aws_iam as iam
import cdk_aws_iotfleetwise as ifw
from constructs import Construct

vehicle_name = 'vin100'
vehicle_can_interface = 'vcan0'

class MyStack(Stack):
  

  def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
    super().__init__(scope, construct_id, **kwargs)

    role = iam.Role(self, "MyRole",
                        assumed_by=iam.ServicePrincipal("iotfleetwise.amazonaws.com"),
                        managed_policies=[
                            iam.ManagedPolicy.from_aws_managed_policy_name("AdministratorAccess")
                        ])
    
    database_name = "FleetWise"
    table_name = "FleetWise"
    database = ts.CfnDatabase(self, "MyDatabase", 
                              database_name=database_name)

    table = ts.CfnTable(self, "MyTable", 
                        database_name=database_name, 
                        table_name=table_name)

    table.node.add_dependency(database)
    
    nodes = [ifw.SignalCatalogBranch(fully_qualified_name='Vehicle')]
    signals_map_my_model = {}
    with open('../dbc/mymodel.dbc') as f:
        lines = f.readlines()
        for line in lines:
            found = re.search(r'^\s+SG_\s+(\w+)\s+.*', line)
            if found:
                signal_name = found.group(1)
                nodes.append(ifw.SignalCatalogSensor(fully_qualified_name=f'Vehicle.{signal_name}', data_type='DOUBLE'))
                signals_map_my_model[signal_name] = f'Vehicle.{signal_name}'

    signal_catalog = ifw.SignalCatalog(self, "FwSignalCatalog",
                                       description='my signal catalog',
                                       nodes=nodes)
    
    

    with open('../dbc/mymodel.dbc') as f:
        my_model = ifw.VehicleModel(self, 'MyModel1',
                                    signal_catalog=signal_catalog,
                                    name='my_model',
                                    description='My Model vehicle',
                                    network_interfaces=[ifw.CanVehicleInterface(interface_id='1', name=f'{vehicle_can_interface}')],
                                    network_file_definitions=[ifw.CanDefinition(
                                       '1',
                                       signals_map_my_model,
                                       [f.read()])])

    vin100 = ifw.Vehicle(self, vehicle_name,
                         vehicle_name=vehicle_name,
                         vehicle_model=my_model,
                         create_iot_thing=True)
    
    ifw.Fleet(self, 'fleet1',
              fleet_id='fleet1',
              signal_catalog=signal_catalog,
              description='my fleet1',
              vehicles=[vin100])
    
    CfnOutput(self, 'privateKey', value=vin100.private_key)
    CfnOutput(self, 'certificate', value=vin100.certificate_pem)
    CfnOutput(self, 'endpointAddress', value=vin100.endpoint_address)
    CfnOutput(self, 'vehicleName', value=vehicle_name)
    CfnOutput(self, 'vehicleCanInterface', value=vehicle_can_interface)

    ifw.Campaign(self, 'MyCampaign',
                 name='my-campaign',
                 target=vin100,
                 collection_scheme=ifw.TimeBasedCollectionScheme(Duration.seconds(10)),
                 signals=[
                   ifw.CampaignSignal('Vehicle.AmbientAirTemperature'),
                   ifw.CampaignSignal('Vehicle.DoorsState'),
                 ],
                 data_destination_configs=[ifw.TimestreamConfigProperty(role.role_arn, table.attr_arn)],
                 auto_approve=True)
