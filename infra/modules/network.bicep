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

@description('Optional. Resource ID of the Log Analytics workspace for VNet diagnostic settings. Leave empty to skip.')
param logAnalyticsWorkspaceId string = ''

var eastVnetName = 'vnet-${prefix}-${env}-east'
var westVnetName = 'vnet-${prefix}-${env}-west'
var delegatedSubnetName = 'snet-pp-delegated'
var privateEndpointSubnetName = 'snet-pep'
var funcAppSubnetName = 'snet-funcapp'

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
      {
        // snet-funcapp: /27 for Function App regional VNet integration.
        // Range 10.10.2.0/27 — does not collide with snet-pp-delegated (10.10.0.0/27)
        // or snet-pep (10.10.1.0/27). Delegated to Microsoft.Web/serverFarms (required
        // for Elastic Premium regional VNet integration).
        name: funcAppSubnetName
        properties: {
          addressPrefix: '10.10.2.0/27'
          delegations: [
            {
              name: 'func-delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
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
output subnetEastFuncAppId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetEast.name, funcAppSubnetName)

// VNet diagnostics — AllMetrics covers VMProtectionAlerts and byte counters.
resource vnetEastDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: 'diag-vnet-east'
  scope: vnetEast
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: []
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}

resource vnetWestDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: 'diag-vnet-west'
  scope: vnetWest
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: []
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}
