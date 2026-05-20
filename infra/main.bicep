targetScope = 'subscription'

@description('Prefix used for all resource names.')
param prefix string = 'pbinet'

@description('Environment suffix used for resource names.')
param env string = 'dev'

@description('Primary Azure region for the east virtual network.')
param regionA string = 'eastus'

@description('Secondary Azure region for the west virtual network.')
param regionB string = 'westus'

@description('Default Azure location for the resource group and shared resources.')
param defaultLocation string = 'westus3'

@description('Power Platform geography for the enterprise policy resource.')
param ppEnvironmentGeography string = 'unitedstates'

@description('Tags applied to deployed resources.')
param tags object = {}

@description('Deploy the Azure SQL resources.')
param deploySql bool = true

@description('Deploy the storage account resources.')
param deployStorage bool = true

var resourceGroupName = 'rg-${prefix}-${env}'

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: defaultLocation
  tags: tags
}

module network 'modules/network.bicep' = {
  name: 'network-${prefix}-${env}'
  scope: rg
  params: {
    prefix: prefix
    env: env
    regionA: regionA
    regionB: regionB
    tags: tags
  }
}

module privateDns 'modules/private-dns.bicep' = {
  name: 'private-dns-${prefix}-${env}'
  scope: rg
  params: {
    vnetEastId: network.outputs.vnetEastId
    vnetWestId: network.outputs.vnetWestId
    tags: tags
  }
}

module managedIdentity 'modules/managed-identity-rbac.bicep' = {
  name: 'uami-${prefix}-${env}'
  scope: rg
  params: {
    prefix: prefix
    env: env
    location: defaultLocation
    tags: tags
  }
}

module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault-${prefix}-${env}'
  scope: rg
  params: {
    prefix: prefix
    env: env
    location: defaultLocation
    tags: tags
    uamiPrincipalId: managedIdentity.outputs.userAssignedIdentityPrincipalId
  }
}

module sql 'modules/sql.bicep' = if (deploySql) {
  name: 'sql-${prefix}-${env}'
  scope: rg
  params: {
    prefix: prefix
    env: env
    location: defaultLocation
    tags: tags
    uamiResourceId: managedIdentity.outputs.userAssignedIdentityResourceId
    uamiPrincipalId: managedIdentity.outputs.userAssignedIdentityPrincipalId
    uamiName: managedIdentity.outputs.userAssignedIdentityName
  }
}

module storage 'modules/storage.bicep' = if (deployStorage) {
  name: 'storage-${prefix}-${env}'
  scope: rg
  params: {
    prefix: prefix
    env: env
    location: defaultLocation
    tags: tags
    uamiPrincipalId: managedIdentity.outputs.userAssignedIdentityPrincipalId
  }
}

module keyVaultPrivateEndpoint 'modules/private-endpoint.bicep' = {
  name: 'pe-kv-${prefix}-${env}'
  scope: rg
  params: {
    name: 'pep-kv-${prefix}-${env}'
    location: regionA
    tags: tags
    subnetId: network.outputs.subnetEastPepId
    targetResourceId: keyVault.outputs.keyVaultId
    groupId: 'vault'
    privateDnsZoneId: privateDns.outputs.kvZoneId
  }
}

module sqlPrivateEndpoint 'modules/private-endpoint.bicep' = if (deploySql) {
  name: 'pe-sql-${prefix}-${env}'
  scope: rg
  params: {
    name: 'pep-sql-${prefix}-${env}'
    location: regionA
    tags: tags
    subnetId: network.outputs.subnetEastPepId
    targetResourceId: sql!.outputs.sqlServerId
    groupId: 'sqlServer'
    privateDnsZoneId: privateDns.outputs.sqlZoneId
  }
}

module storagePrivateEndpoint 'modules/private-endpoint.bicep' = if (deployStorage) {
  name: 'pe-stg-${prefix}-${env}'
  scope: rg
  params: {
    name: 'pep-stg-${prefix}-${env}'
    location: regionA
    tags: tags
    subnetId: network.outputs.subnetEastPepId
    targetResourceId: storage!.outputs.storageAccountId
    groupId: 'blob'
    privateDnsZoneId: privateDns.outputs.blobZoneId
  }
}

module enterprisePolicy 'modules/enterprise-policy.bicep' = {
  name: 'enterprise-policy-${prefix}-${env}'
  scope: rg
  params: {
    prefix: prefix
    env: env
    location: defaultLocation
    tags: tags
    vnetEastId: network.outputs.vnetEastId
    vnetWestId: network.outputs.vnetWestId
    ppGeographyName: ppEnvironmentGeography
  }
}

output enterprisePolicyArmId string = enterprisePolicy.outputs.enterprisePolicyArmId
output keyVaultName string = keyVault.outputs.keyVaultName
output keyVaultUri string = keyVault.outputs.keyVaultUri
output sqlServerFqdn string = deploySql ? sql!.outputs.sqlServerFqdn : ''
output sqlDatabaseName string = deploySql ? sql!.outputs.sqlDatabaseName : ''
output storageAccountName string = deployStorage ? storage!.outputs.storageAccountName : ''
output userAssignedIdentityResourceId string = managedIdentity.outputs.userAssignedIdentityResourceId
output userAssignedIdentityPrincipalId string = managedIdentity.outputs.userAssignedIdentityPrincipalId
output vnetEastId string = network.outputs.vnetEastId
output vnetWestId string = network.outputs.vnetWestId
