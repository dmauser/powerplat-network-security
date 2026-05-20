@description('Prefix used for all resource names.')
param prefix string

@description('Environment suffix used for resource names.')
param env string

@description('Azure location context for the enterprise policy deployment.')
param location string

@description('Tags applied to deployed resources.')
param tags object

@description('Resource ID of the east virtual network hosting the delegated subnet.')
param vnetEastId string

@description('Resource ID of the west virtual network hosting the delegated subnet.')
param vnetWestId string

@description('Power Platform geography used as the enterprise policy location value.')
param ppGeographyName string

var enterprisePolicyName = 'ep-${prefix}-${env}'
var delegatedSubnetName = 'snet-pp-delegated'

resource enterprisePolicy 'Microsoft.PowerPlatform/enterprisePolicies@2020-10-30-preview' = {
  name: enterprisePolicyName
  location: empty(ppGeographyName) ? location : ppGeographyName
  kind: 'NetworkInjection'
  tags: tags
  properties: {
    networkInjection: {
      virtualNetworks: [
        {
          id: vnetEastId
          subnet: {
            name: delegatedSubnetName
          }
        }
        {
          id: vnetWestId
          subnet: {
            name: delegatedSubnetName
          }
        }
      ]
    }
  }
}

output enterprisePolicyArmId string = enterprisePolicy.id
output enterprisePolicyName string = enterprisePolicy.name
