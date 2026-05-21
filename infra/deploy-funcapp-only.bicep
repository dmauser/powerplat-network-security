// deploy-funcapp-only.bicep
// Targeted resource-group-scope template that deploys ONLY the dual-region Function Apps
// and their private endpoints. Used when the full main.bicep run is blocked by pre-existing
// resource conflicts (EP already linked, KV role assignment exists, SQL region capacity).
//
// Existing resources referenced (not re-deployed):
//   - kv-pbinet-dev-k6ozyjreme            Key Vault (east)
//   - appi-pbinet-dev                     Application Insights
//   - law-pbinet-dev-k6ozyjremes6m        Log Analytics Workspace
//   - vnet-pbinet-dev-east / west         VNets + snet-funcapp subnets
//   - privatelink.azurewebsites.net       Private DNS zone
//   - privatelink.blob.core.windows.net   Private DNS zone
//   - privatelink.file.core.windows.net   Private DNS zone

targetScope = 'resourceGroup'

param prefix string = 'pbinet'
param env    string = 'dev'
param tags   object = { env: 'dev', project: 'pp-vnet-keyvault-demo' }

@description('App Service Plan SKU. Override to S1/P1v2 if EP1 quota is unavailable. Do NOT use Y1 (Consumption) — it lacks regional VNet integration.')
param aspSkuName string = 'EP1'
@description('SKU tier matching aspSkuName.')
param aspSkuTier string = 'ElasticPremium'

var regionA = 'eastus'
var regionB = 'westus'

var keyVaultName        = 'kv-${prefix}-${env}-k6ozyjreme'
var appInsightsName     = 'appi-${prefix}-${env}'
var lawName             = 'law-${prefix}-${env}-k6ozyjremes6m'
var vnetEastName        = 'vnet-${prefix}-${env}-east'
var vnetWestName        = 'vnet-${prefix}-${env}-west'

// ---------------------------------------------------------------------------
// Existing resource references
// ---------------------------------------------------------------------------
resource existingLaw 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: lawName
}

resource existingPepSubnetEast 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  name: '${vnetEastName}/snet-pep'
}

resource existingPepSubnetWest 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  name: '${vnetWestName}/snet-pep'
}

resource existingFuncSubnetEast 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  name: '${vnetEastName}/snet-funcapp'
}

resource existingFuncSubnetWest 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  name: '${vnetWestName}/snet-funcapp'
}

resource websitesZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  #disable-next-line no-hardcoded-env-urls
  name: 'privatelink.azurewebsites.net'
}

resource blobZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  #disable-next-line no-hardcoded-env-urls
  name: 'privatelink.blob.core.windows.net'
}

resource fileZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  #disable-next-line no-hardcoded-env-urls
  name: 'privatelink.file.core.windows.net'
}

// ---------------------------------------------------------------------------
// Function Apps (dual-region)
// ---------------------------------------------------------------------------
module funcAppEast 'modules/funcapp.bicep' = {
  name: 'funcapp-east-${prefix}-${env}'
  params: {
    prefix: prefix
    env: env
    regionSuffix: 'east'
    location: regionA
    tags: tags
    funcSubnetId: existingFuncSubnetEast.id
    appInsightsName: appInsightsName
    keyVaultName: keyVaultName
    logAnalyticsWorkspaceId: existingLaw.id
    aspSkuName: aspSkuName
    aspSkuTier: aspSkuTier
  }
}

module funcAppWest 'modules/funcapp.bicep' = {
  name: 'funcapp-west-${prefix}-${env}'
  params: {
    prefix: prefix
    env: env
    regionSuffix: 'west'
    location: regionB
    tags: tags
    funcSubnetId: existingFuncSubnetWest.id
    appInsightsName: appInsightsName
    keyVaultName: keyVaultName
    logAnalyticsWorkspaceId: existingLaw.id
    aspSkuName: aspSkuName
    aspSkuTier: aspSkuTier
  }
}

// ---------------------------------------------------------------------------
// Private Endpoints
// ---------------------------------------------------------------------------
module funcAppEastPe 'modules/private-endpoint.bicep' = {
  name: 'pe-func-east-${prefix}-${env}'
  params: {
    name: 'pep-func-east-${prefix}-${env}'
    location: regionA
    tags: tags
    subnetId: existingPepSubnetEast.id
    targetResourceId: funcAppEast.outputs.functionAppResourceId
    groupId: 'sites'
    privateDnsZoneId: websitesZone.id
  }
}

module funcAppWestPe 'modules/private-endpoint.bicep' = {
  name: 'pe-func-west-${prefix}-${env}'
  params: {
    name: 'pep-func-west-${prefix}-${env}'
    location: regionB
    tags: tags
    subnetId: existingPepSubnetWest.id
    targetResourceId: funcAppWest.outputs.functionAppResourceId
    groupId: 'sites'
    privateDnsZoneId: websitesZone.id
  }
}

module funcStorageEastBlobPe 'modules/private-endpoint.bicep' = {
  name: 'pe-funcstg-blob-east-${prefix}-${env}'
  params: {
    name: 'pep-funcstg-blob-east-${prefix}-${env}'
    location: regionA
    tags: tags
    subnetId: existingPepSubnetEast.id
    targetResourceId: funcAppEast.outputs.funcStorageAccountId
    groupId: 'blob'
    privateDnsZoneId: blobZone.id
  }
}

module funcStorageEastFilePe 'modules/private-endpoint.bicep' = {
  name: 'pe-funcstg-file-east-${prefix}-${env}'
  params: {
    name: 'pep-funcstg-file-east-${prefix}-${env}'
    location: regionA
    tags: tags
    subnetId: existingPepSubnetEast.id
    targetResourceId: funcAppEast.outputs.funcStorageAccountId
    groupId: 'file'
    privateDnsZoneId: fileZone.id
  }
}

module funcStorageWestBlobPe 'modules/private-endpoint.bicep' = {
  name: 'pe-funcstg-blob-west-${prefix}-${env}'
  params: {
    name: 'pep-funcstg-blob-west-${prefix}-${env}'
    location: regionB
    tags: tags
    subnetId: existingPepSubnetWest.id
    targetResourceId: funcAppWest.outputs.funcStorageAccountId
    groupId: 'blob'
    privateDnsZoneId: blobZone.id
  }
}

module funcStorageWestFilePe 'modules/private-endpoint.bicep' = {
  name: 'pe-funcstg-file-west-${prefix}-${env}'
  params: {
    name: 'pep-funcstg-file-west-${prefix}-${env}'
    location: regionB
    tags: tags
    subnetId: existingPepSubnetWest.id
    targetResourceId: funcAppWest.outputs.funcStorageAccountId
    groupId: 'file'
    privateDnsZoneId: fileZone.id
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output functionAppEastName     string = funcAppEast.outputs.functionAppName
output functionAppEastHostname string = funcAppEast.outputs.functionAppHostname
output functionAppWestName     string = funcAppWest.outputs.functionAppName
output functionAppWestHostname string = funcAppWest.outputs.functionAppHostname
