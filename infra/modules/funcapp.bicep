// =============================================================================
// Function App module — Part 4 demo (App Insights dependency tracking)
//
// Deploys:
//   - Function storage account (publicNetworkAccess=Disabled, allowSharedKeyAccess=false)
//   - App Service Plan (Elastic Premium EP1, Linux) — required for regional VNet
//     integration with private-endpoint dependencies; Consumption plan does NOT
//     support outbound VNet integration to private endpoints reliably.
//   - Function App (Linux, PowerShell 7.4, system-assigned MI, publicNetworkAccess=Disabled)
//   - Regional VNet integration into snet-funcapp /27 (delegated Microsoft.Web/serverFarms)
//   - RBAC: Key Vault Secrets User on existing demo KV (existing ref — no redeploy)
//   - RBAC: Storage Blob Data Owner + Storage Account Contributor on function storage
//     (required for keyless AzureWebJobsStorage via MI)
//   - Diagnostic settings → Log Analytics
//
// NOTE: publicNetworkAccess=Disabled blocks the SCM (Kudu) endpoint publicly.
// Tank must deploy function code through the private endpoint or a jump host on the VNet.
// =============================================================================

@description('Prefix used for all resource names.')
param prefix string

@description('Environment suffix used for resource names.')
param env string

@description('Region suffix used to disambiguate dual-region deployments (e.g., "east" or "west"). Appended to resource names to prevent collisions when both regions deploy into the same resource group.')
param regionSuffix string

@description('Azure region for the Function App deployment.')
param location string

@description('Tags applied to deployed resources.')
param tags object

@description('Resource ID of the snet-funcapp subnet for regional VNet integration (10.10.2.0/27, delegated to Microsoft.Web/serverFarms).')
param funcSubnetId string

@description('Name of the existing Application Insights resource (appi-{prefix}-{env}) for dependency tracking connection string.')
param appInsightsName string

@description('Name of the existing demo Key Vault to grant Key Vault Secrets User to the Function App MI.')
param keyVaultName string

@description('Optional. Resource ID of the Log Analytics workspace for diagnostic settings. Leave empty to skip.')
param logAnalyticsWorkspaceId string = ''

@description('App Service Plan SKU name. Use EP1/EP2/EP3 for Elastic Premium (recommended; requires compute quota). Use S1/P1v2 for Dedicated when EP quota is unavailable. Consumption (Y1/Dynamic) does NOT support regional VNet integration and must not be used with private endpoints.')
param aspSkuName string = 'EP1'

@description('App Service Plan SKU tier. Must match aspSkuName: ElasticPremium for EP*, Standard for S*, PremiumV2 for P*v2.')
param aspSkuTier string = 'ElasticPremium'

// ---------------------------------------------------------------------------
// Role definition IDs (built-in, tenant-invariant)
// ---------------------------------------------------------------------------
var keyVaultSecretsUserRoleDefinitionId        = '4633458b-17de-408a-b874-0445c86b69e6'
var storageBlobDataOwnerRoleDefinitionId       = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var storageAccountContributorRoleDefinitionId  = '17d1049b-9a84-46fb-8f53-869881c3d3ab'

// ---------------------------------------------------------------------------
// Resource names
// ---------------------------------------------------------------------------
// Function storage: must be globally unique, 3-24 lowercase alphanumeric.
// regionSuffix ('east'/'west') disambiguates the two instances in the same RG.
// Pattern: stfunc{regionSuffix}{uniqueString} — max 23 chars (well within the 24 limit).
var funcStorageAccountName = toLower(take('stfunc${regionSuffix}${uniqueString(resourceGroup().id)}', 24))
var appServicePlanName     = 'asp-${prefix}-${env}-${regionSuffix}'
var funcAppName            = 'func-${prefix}-${env}-${regionSuffix}'

// ---------------------------------------------------------------------------
// Existing resource references
// ---------------------------------------------------------------------------
resource existingAppInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

resource existingKeyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// ---------------------------------------------------------------------------
// Function App runtime storage
// Separate from the demo storage account. allowSharedKeyAccess=false forces
// the Functions runtime to authenticate via MI (AzureWebJobsStorage__ format).
// ---------------------------------------------------------------------------
resource funcStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: funcStorageAccountName
  location: location
  tags: tags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Disabled'
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'None'
    }
  }
}

// ---------------------------------------------------------------------------
// App Service Plan — Elastic Premium EP1 (Linux)
// EP1 is required for regional VNet integration with private-endpoint
// dependencies. Consumption plan does not support outbound VNet integration
// to private endpoints reliably.
// ---------------------------------------------------------------------------
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: aspSkuName
    tier: aspSkuTier
  }
  kind: aspSkuTier == 'ElasticPremium' ? 'elastic' : 'linux'
  properties: {
    reserved: true // Linux
    maximumElasticWorkerCount: aspSkuTier == 'ElasticPremium' ? 20 : null
  }
}

// ---------------------------------------------------------------------------
// Function App
// ---------------------------------------------------------------------------
resource funcApp 'Microsoft.Web/sites@2023-12-01' = {
  name: funcAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    publicNetworkAccess: 'Disabled'
    siteConfig: {
      linuxFxVersion: 'PowerShell|7.4'
      // Route ALL outbound traffic through the VNet so private DNS resolves KV/storage
      // private endpoints instead of public FQDNs.
      vnetRouteAllEnabled: true
      functionsRuntimeScaleMonitoringEnabled: true
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: existingAppInsights.properties.ConnectionString
        }
        {
          name: 'KEY_VAULT_NAME'
          value: keyVaultName
        }
        {
          name: 'REGION'
          value: regionSuffix
        }
        {
          name: 'SECRET_NAME'
          value: 'demo-secret'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'powershell'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          // Tank sets the actual package URL (or runs az functionapp deployment source config-zip)
          // during demo preparation. '1' enables run-from-package mode.
          value: '1'
        }
        {
          // MI-based WebJobs storage — no shared key required.
          // allowSharedKeyAccess=false on the storage account enforces this.
          name: 'AzureWebJobsStorage__accountName'
          value: funcStorageAccountName
        }
        {
          // Tells the Functions v4 runtime to use managed identity for storage auth.
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
      ]
    }
  }
}

// Regional VNet integration into snet-funcapp.
// swiftSupported=true enables the current (non-legacy) regional VNet integration path.
resource funcAppVnetIntegration 'Microsoft.Web/sites/networkConfig@2023-12-01' = {
  name: 'virtualNetwork'
  parent: funcApp
  properties: {
    subnetResourceId: funcSubnetId
    swiftSupported: true
  }
}

// ---------------------------------------------------------------------------
// RBAC
// ---------------------------------------------------------------------------

// Key Vault Secrets User — allows the Function App MI to call GetSecret()
// on demo-secret via the private endpoint path.
resource kvSecretsUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(existingKeyVault.id, funcApp.id, keyVaultSecretsUserRoleDefinitionId)
  scope: existingKeyVault
  properties: {
    principalId: funcApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleDefinitionId)
  }
}

// Storage Blob Data Owner — primary role for MI-based AzureWebJobsStorage.
// NOTE: If Tank observes runtime errors about queue/table operations, also add
// Storage Queue Data Contributor + Storage Table Data Contributor on funcStorageAccount.
resource storageBlobDataOwnerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(funcStorageAccount.id, funcApp.id, storageBlobDataOwnerRoleDefinitionId)
  scope: funcStorageAccount
  properties: {
    principalId: funcApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleDefinitionId)
  }
}

// Storage Account Contributor — required alongside Blob Data Owner for
// full MI-based WebJobs storage management.
resource storageAccountContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(funcStorageAccount.id, funcApp.id, storageAccountContributorRoleDefinitionId)
  scope: funcStorageAccount
  properties: {
    principalId: funcApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageAccountContributorRoleDefinitionId)
  }
}

// ---------------------------------------------------------------------------
// Diagnostic settings
// ---------------------------------------------------------------------------
resource funcAppDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: 'diag-func'
  scope: funcApp
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { category: 'FunctionAppLogs', enabled: true }
    ]
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output functionAppName string = funcApp.name
output functionAppResourceId string = funcApp.id
output functionAppPrincipalId string = funcApp.identity.principalId
output functionAppHostname string = funcApp.properties.defaultHostName
output funcStorageAccountName string = funcStorageAccountName
output funcStorageAccountId string = funcStorageAccount.id
