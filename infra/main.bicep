targetScope = 'subscription'

@description('Prefix used for all resource names.')
param prefix string = 'pbinet'

@description('Environment suffix used for resource names.')
param env string = 'dev'

@description('Primary Azure region for the east virtual network.')
param regionA string = 'eastus'

@description('Secondary Azure region for the west virtual network.')
param regionB string = 'westus'

@description('Default Azure location for the resource group and shared resources. Defaults to eastus, matching the primary paired region for the United States Power Platform geography.')
param defaultLocation string = 'eastus'

@description('Power Platform geography for the enterprise policy resource.')
param ppEnvironmentGeography string = 'unitedstates'

@description('Tags applied to deployed resources.')
param tags object = {}

@description('Deploy the Azure SQL resources.')
param deploySql bool = true

@description('Deploy the storage account resources.')
param deployStorage bool = true

@description('Log Analytics workspace data retention in days (30-730).')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 30

@description('Enable Azure Monitor alert rules. Set true to activate alerts; false deploys only the action group stub.')
param enableAlerts bool = false

var resourceGroupName = 'rg-${prefix}-${env}'

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: defaultLocation
  tags: tags
}

// Log Analytics workspace — deployed first as a dependency for all diagnostic settings.
module logAnalytics 'modules/logAnalytics.bicep' = {
  name: 'law-${prefix}-${env}'
  scope: rg
  params: {
    prefix: prefix
    env: env
    location: defaultLocation
    tags: tags
    retentionInDays: logAnalyticsRetentionDays
  }
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

// Diagnostic settings
// Key Vault — AuditEvent is the primary signal: every authenticated KV operation
// records caller identity, source IP, operation name, and result. A source IP in the
// delegated-subnet range confirms Power Platform reached KV over the private endpoint.
module diagKv 'modules/diagnosticSettings.bicep' = {
  name: 'diag-kv-${prefix}-${env}'
  scope: rg
  params: {
    targetResourceId: keyVault.outputs.keyVaultId
    workspaceId: logAnalytics.outputs.workspaceId
    settingName: 'diag-kv'
    logs: [
      { category: 'AuditEvent',                  enabled: true }
      { category: 'AzurePolicyEvaluationDetails', enabled: true }
    ]
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}

// Storage account blob service — diagnostics target the blobServices child resource.
module diagBlob 'modules/diagnosticSettings.bicep' = if (deployStorage) {
  name: 'diag-blob-${prefix}-${env}'
  scope: rg
  params: {
    targetResourceId: '${storage!.outputs.storageAccountId}/blobServices/default'
    workspaceId: logAnalytics.outputs.workspaceId
    settingName: 'diag-blob'
    logs: [
      { category: 'StorageRead',   enabled: true }
      { category: 'StorageWrite',  enabled: true }
      { category: 'StorageDelete', enabled: true }
    ]
    metrics: [
      { category: 'Transaction', enabled: true }
    ]
  }
}

// Azure SQL Database — diagnostics on the database resource (not the server).
module diagSqlDb 'modules/diagnosticSettings.bicep' = if (deploySql) {
  name: 'diag-sqldb-${prefix}-${env}'
  scope: rg
  params: {
    targetResourceId: sql!.outputs.sqlDatabaseId
    workspaceId: logAnalytics.outputs.workspaceId
    settingName: 'diag-sqldb'
    logs: [
      { category: 'SQLSecurityAuditEvents',  enabled: true }
      { category: 'Errors',                  enabled: true }
      { category: 'Timeouts',                enabled: true }
    ]
    metrics: [
      { category: 'Basic',                   enabled: true }
      { category: 'InstanceAndAppAdvanced',  enabled: true }
    ]
  }
}

// Private endpoints — metrics only (no log categories exist for PE resources).
// PEBytesIn/Out and PEConnectionsConnected are the key health signals.
module diagPeKv 'modules/diagnosticSettings.bicep' = {
  name: 'diag-pe-kv-${prefix}-${env}'
  scope: rg
  params: {
    targetResourceId: keyVaultPrivateEndpoint.outputs.privateEndpointId
    workspaceId: logAnalytics.outputs.workspaceId
    settingName: 'diag-pe-kv'
    logs: []
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}

module diagPeSql 'modules/diagnosticSettings.bicep' = if (deploySql) {
  name: 'diag-pe-sql-${prefix}-${env}'
  scope: rg
  params: {
    targetResourceId: sqlPrivateEndpoint!.outputs.privateEndpointId
    workspaceId: logAnalytics.outputs.workspaceId
    settingName: 'diag-pe-sql'
    logs: []
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}

module diagPeBlob 'modules/diagnosticSettings.bicep' = if (deployStorage) {
  name: 'diag-pe-blob-${prefix}-${env}'
  scope: rg
  params: {
    targetResourceId: storagePrivateEndpoint!.outputs.privateEndpointId
    workspaceId: logAnalytics.outputs.workspaceId
    settingName: 'diag-pe-blob'
    logs: []
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}

// VNet diagnostics — AllMetrics covers VMProtectionAlerts and byte counters.
module diagVnetEast 'modules/diagnosticSettings.bicep' = {
  name: 'diag-vnet-east-${prefix}-${env}'
  scope: rg
  params: {
    targetResourceId: network.outputs.vnetEastId
    workspaceId: logAnalytics.outputs.workspaceId
    settingName: 'diag-vnet-east'
    logs: []
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}

module diagVnetWest 'modules/diagnosticSettings.bicep' = {
  name: 'diag-vnet-west-${prefix}-${env}'
  scope: rg
  params: {
    targetResourceId: network.outputs.vnetWestId
    workspaceId: logAnalytics.outputs.workspaceId
    settingName: 'diag-vnet-west'
    logs: []
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}

// Alerts module — action group always deployed; alert rules conditioned on enableAlerts.
module alerts 'modules/alerts.bicep' = {
  name: 'alerts-${prefix}-${env}'
  scope: rg
  params: {
    prefix: prefix
    env: env
    location: defaultLocation
    tags: tags
    workspaceId: logAnalytics.outputs.workspaceId
    keyVaultId: keyVault.outputs.keyVaultId
    kvPeId: keyVaultPrivateEndpoint.outputs.privateEndpointId
    sqlPeId: deploySql ? sqlPrivateEndpoint!.outputs.privateEndpointId : ''
    blobPeId: deployStorage ? storagePrivateEndpoint!.outputs.privateEndpointId : ''
    enableAlerts: enableAlerts
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
// Canonical LAW output names — referenced by Niobe (docs/monitoring.md) and Tank (App Insights).
output logAnalyticsWorkspaceName string = logAnalytics.outputs.workspaceName
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId