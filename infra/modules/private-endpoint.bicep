@description('Name of the private endpoint resource.')
param name string

@description('Azure location for the private endpoint.')
param location string

@description('Tags applied to deployed resources.')
param tags object

@description('Resource ID of the subnet hosting the private endpoint.')
param subnetId string

@description('Resource ID of the target private link resource.')
param targetResourceId string

@description('Private link group ID exposed by the target resource.')
param groupId string

@description('Resource ID of the private DNS zone associated with the target resource.')
param privateDnsZoneId string

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${name}-connection'
        properties: {
          privateLinkServiceId: targetResourceId
          groupIds: [
            groupId
          ]
          requestMessage: 'Provisioned by Bicep deployment.'
        }
      }
    ]
  }
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  name: 'default'
  parent: privateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: '${groupId}-config'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

output privateEndpointId string = privateEndpoint.id
output privateEndpointName string = privateEndpoint.name
// Note: Microsoft.Network/privateEndpoints does not support Microsoft.Insights/diagnosticSettings.
// PE health is monitored via Azure Monitor metrics (PEConnectionsConnected, PEBytesIn/Out)
// accessible directly through the Azure portal Metrics blade — no diag setting needed.
