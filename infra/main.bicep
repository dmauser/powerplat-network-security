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

@description('Optional override for the resource group name. When non-empty this value is used instead of the computed "rg-{prefix}-{env}" pattern. Set in parameters for environment-specific naming (e.g., rg-pbinet-dev-eastus).')
param resourceGroupNameOverride string = ''

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

@description('Optional. Object IDs of interactive users (e.g., the demo operator) granted Key Vault Secrets User on the demo vault. Required for the Power Apps Key Vault connector (per-user OAuth) to read demo-secret. scripts/01-deploy.sh populates this with the current signed-in user when not overridden.')
param demoUserPrincipalIds array = []

var resourceGroupName = empty(resourceGroupNameOverride) ? 'rg-${prefix}-${env}' : resourceGroupNameOverride

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

module nsp 'modules/nsp.bicep' = {
  name: 'nsp-${prefix}-${env}'
  scope: rg
  params: {
    prefix: prefix
    env: env
    location: defaultLocation
    tags: tags
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
  }
}

// Application Insights — workspace-based, linked to the LAW above.
// Provides Power Platform telemetry correlation (Managed Environment → LAW).
module appInsights 'modules/appInsights.bicep' = {
  name: 'appi-${prefix}-${env}'
  scope: rg
  params: {
    prefix: prefix
    env: env
    location: defaultLocation
    tags: tags
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
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
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
  }
}

module flowLogsStorage 'modules/flow-logs-storage.bicep' = {
  name: 'flowlogs-storage-${prefix}-${env}'
  scope: rg
  params: {
    prefix: prefix
    env: env
    location: defaultLocation
    tags: tags
  }
}

module flowLogEast 'modules/flow-logs.bicep' = {
  name: 'flowlog-east-${prefix}-${env}'
  scope: resourceGroup('NetworkWatcherRG')
  params: {
    location: regionA
    flowLogName: 'fl-vnet-${prefix}-${env}-east'
    vnetId: network.outputs.vnetEastId
    storageAccountId: flowLogsStorage.outputs.storageAccountId
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    logAnalyticsWorkspaceRegion: defaultLocation
    logAnalyticsWorkspaceGuid: logAnalytics.outputs.customerId
    tags: tags
    networkWatcherName: 'NetworkWatcher_${regionA}'
  }
}

module flowLogWest 'modules/flow-logs.bicep' = {
  name: 'flowlog-west-${prefix}-${env}'
  scope: resourceGroup('NetworkWatcherRG')
  params: {
    location: regionB
    flowLogName: 'fl-vnet-${prefix}-${env}-west'
    vnetId: network.outputs.vnetWestId
    storageAccountId: flowLogsStorage.outputs.storageAccountId
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    logAnalyticsWorkspaceRegion: defaultLocation
    logAnalyticsWorkspaceGuid: logAnalytics.outputs.customerId
    tags: tags
    networkWatcherName: 'NetworkWatcher_${regionB}'
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
    demoUserPrincipalIds: demoUserPrincipalIds
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
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
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
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
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
  }
}

module nspAssociationKv 'modules/nsp-association.bicep' = {
  name: 'nsp-assoc-kv-${prefix}-${env}'
  scope: rg
  params: {
    nspName: nsp.outputs.nspName
    profileName: nsp.outputs.nspProfileName
    targetResourceId: keyVault.outputs.keyVaultId
    associationName: 'assoc-kv'
  }
}

module nspAssociationSql 'modules/nsp-association.bicep' = if (deploySql) {
  name: 'nsp-assoc-sql-${prefix}-${env}'
  scope: rg
  params: {
    nspName: nsp.outputs.nspName
    profileName: nsp.outputs.nspProfileName
    targetResourceId: sql!.outputs.sqlServerId
    associationName: 'assoc-sql'
  }
  dependsOn: [
    nspAssociationKv
  ]
}

module nspAssociationStorage 'modules/nsp-association.bicep' = if (deployStorage) {
  name: 'nsp-assoc-storage-${prefix}-${env}'
  scope: rg
  params: {
    nspName: nsp.outputs.nspName
    profileName: nsp.outputs.nspProfileName
    targetResourceId: storage!.outputs.storageAccountId
    associationName: 'assoc-storage'
  }
  dependsOn: deploySql
    ? [
        nspAssociationKv
        nspAssociationSql
      ]
    : [
        nspAssociationKv
      ]
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

// Diagnostic settings are now co-located in each resource module (keyvault, storage, sql,
// network, private-endpoint). Passing logAnalyticsWorkspaceId to each module activates
// them inline, using typed 'existing' scope references — the correct Bicep pattern.
// (The generic diagnosticSettings.bicep/inner-json approach fails because Bicep escapes
// '[' → '[[' in object-literal strings, preventing ARM expression evaluation at runtime.)

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
output nspName string = nsp.outputs.nspName
output nspId string = nsp.outputs.nspId
output sqlServerFqdn string = deploySql ? sql!.outputs.sqlServerFqdn : ''
output sqlDatabaseName string = deploySql ? sql!.outputs.sqlDatabaseName : ''
output storageAccountName string = deployStorage ? storage!.outputs.storageAccountName : ''
output flowLogsStorageName string = flowLogsStorage.outputs.storageAccountName
output userAssignedIdentityResourceId string = managedIdentity.outputs.userAssignedIdentityResourceId
output userAssignedIdentityPrincipalId string = managedIdentity.outputs.userAssignedIdentityPrincipalId
output vnetEastId string = network.outputs.vnetEastId
output vnetWestId string = network.outputs.vnetWestId
// Canonical LAW output names — referenced by Niobe (docs/monitoring.md) and Tank (App Insights).
output logAnalyticsWorkspaceName string = logAnalytics.outputs.workspaceName
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
// App Insights outputs — consumed by scripts/02-configure-pp-vnet.ps1 for PP Managed Environment binding.
output appInsightsName string = appInsights.outputs.appInsightsName
output appInsightsConnectionString string = appInsights.outputs.appInsightsConnectionString