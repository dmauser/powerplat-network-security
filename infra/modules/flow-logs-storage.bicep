@description('Prefix used for all resource names.')
param prefix string

@description('Environment suffix used for resource names.')
param env string

@description('Azure location for the flow logs storage account.')
param location string

@description('Tags applied to deployed resources.')
param tags object

var storageAccountName = toLower(take('st${prefix}fl${env}${uniqueString(resourceGroup().id)}', 24))

resource flowLogsStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Enabled'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    isHnsEnabled: false
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

resource lifecyclePolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2023-05-01' = {
  name: 'default'
  parent: flowLogsStorage
  properties: {
    policy: {
      rules: [
        {
          name: 'delete-after-30-days'
          enabled: true
          type: 'Lifecycle'
          definition: {
            actions: {
              baseBlob: {
                delete: {
                  daysAfterModificationGreaterThan: 30
                }
              }
            }
            filters: {
              blobTypes: [
                'blockBlob'
              ]
            }
          }
        }
      ]
    }
  }
}

output storageAccountId string = flowLogsStorage.id
output storageAccountName string = flowLogsStorage.name
