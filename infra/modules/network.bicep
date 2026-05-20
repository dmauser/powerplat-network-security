@description('Prefix used for all resource names.')
param prefix string

@description('Environment suffix used for resource names.')
param env string

@description('Primary Azure region for the east virtual network.')
param regionA string

@description('Secondary Azure region for the west virtual network.')
param regionB string

@description('Tags applied to deployed resources.')
param tags object

var eastVnetName = 'vnet-${prefix}-${env}-east'
var westVnetName = 'vnet-${prefix}-${env}-west'
var delegatedSubnetName = 'snet-pp-delegated'
var privateEndpointSubnetName = 'snet-pep'

resource vnetEast 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: eastVnetName
  location: regionA
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.10.0.0/16'
      ]
    }
    subnets: [
      {
        name: delegatedSubnetName
        properties: {
          addressPrefix: '10.10.0.0/27'
          delegations: [
            {
              name: 'pp-delegation'
              properties: {
                serviceName: 'Microsoft.PowerPlatform/enterprisePolicies'
              }
            }
          ]
        }
      }
      {
        name: privateEndpointSubnetName
        properties: {
          addressPrefix: '10.10.1.0/27'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource vnetWest 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: westVnetName
  location: regionB
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.20.0.0/16'
      ]
    }
    subnets: [
      {
        name: delegatedSubnetName
        properties: {
          addressPrefix: '10.20.0.0/27'
          delegations: [
            {
              name: 'pp-delegation'
              properties: {
                serviceName: 'Microsoft.PowerPlatform/enterprisePolicies'
              }
            }
          ]
        }
      }
      {
        name: privateEndpointSubnetName
        properties: {
          addressPrefix: '10.20.1.0/27'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource eastToWestPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  name: 'peer-${eastVnetName}-to-${westVnetName}'
  parent: vnetEast
  properties: {
    remoteVirtualNetwork: {
      id: vnetWest.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

resource westToEastPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  name: 'peer-${westVnetName}-to-${eastVnetName}'
  parent: vnetWest
  properties: {
    remoteVirtualNetwork: {
      id: vnetEast.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

output vnetEastId string = vnetEast.id
output vnetWestId string = vnetWest.id
output subnetEastDelegatedId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetEast.name, delegatedSubnetName)
output subnetWestDelegatedId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetWest.name, delegatedSubnetName)
output subnetEastPepId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetEast.name, privateEndpointSubnetName)
output subnetWestPepId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetWest.name, privateEndpointSubnetName)
