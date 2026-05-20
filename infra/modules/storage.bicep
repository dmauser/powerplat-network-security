@description('Prefix used for all resource names.')
param prefix string

@description('Environment suffix used for resource names.')
param env string

@description('Azure location for the storage deployment.')
param location string

@description('Tags applied to deployed resources.')
param tags object

@description('Principal ID of the user-assigned managed identity granted blob reader access.')
param uamiPrincipalId string

var storageBlobDataReaderRoleDefinitionId = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
var storageAccountName = toLower(take('st${prefix}${env}${uniqueString(resourceGroup().id)}', 24))

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Disabled'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  name: 'default'
  parent: storageAccount
}

resource demoContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: 'demo'
  parent: blobService
  properties: {
    publicAccess: 'None'
  }
}

resource storageBlobDataReaderAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, uamiPrincipalId, storageBlobDataReaderRoleDefinitionId)
  scope: storageAccount
  properties: {
    principalId: uamiPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataReaderRoleDefinitionId)
  }
}

output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob
