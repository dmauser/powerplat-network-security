# Skill: Add a VNet-integrated Function App to this lab

**Repo:** powerplat-network-security  
**Author:** Trinity  
**Date:** 2026-05-21

---

## When to use this skill

When the lab needs an Azure Function App that:
- Runs inside the East VNet (outbound via VNet, inbound via private endpoint)
- Accesses private-endpoint-protected dependencies (Key Vault, SQL, Storage) without public network access
- Emits telemetry to the existing App Insights workspace for dependency tracking

---

## Pattern summary

### 1. Add a delegated subnet to the East VNet (`network.bicep`)

```bicep
var funcAppSubnetName = 'snet-funcapp'

// Inside vnetEast.properties.subnets array:
{
  name: funcAppSubnetName
  properties: {
    addressPrefix: '10.10.2.0/27'   // next available /27 block
    delegations: [
      {
        name: 'func-delegation'
        properties: { serviceName: 'Microsoft.Web/serverFarms' }
      }
    ]
  }
}

// Output:
output subnetEastFuncAppId string = resourceId(
  'Microsoft.Network/virtualNetworks/subnets', vnetEast.name, funcAppSubnetName)
```

**Rule:** Never use `service endpoints` on this subnet — we use private endpoints for outbound dependency access, not service endpoints.

---

### 2. Choose Elastic Premium EP1 — NOT Consumption

| Plan | VNet integration to PEs | Notes |
|---|---|---|
| **EP1 (Elastic Premium)** | ✅ Yes | `vnetRouteAllEnabled=true` supported and enforced |
| Consumption (Y1) | ❌ Unreliable | VNet integration exists but doesn't support routing all outbound traffic to private endpoints reliably |

```bicep
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  sku: { name: 'EP1', tier: 'ElasticPremium' }
  kind: 'elastic'
  properties: { reserved: true, maximumElasticWorkerCount: 20 }
}
```

---

### 3. Function App configuration

```bicep
resource funcApp 'Microsoft.Web/sites@2023-12-01' = {
  kind: 'functionapp,linux'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    publicNetworkAccess: 'Disabled'
    siteConfig: {
      linuxFxVersion: 'PowerShell|7.4'
      vnetRouteAllEnabled: true
      functionsRuntimeScaleMonitoringEnabled: true
      appSettings: [ ... ]
    }
  }
}
```

**Regional VNet integration** (must be a separate child resource — not an inline property):
```bicep
resource funcAppVnetIntegration 'Microsoft.Web/sites/networkConfig@2023-12-01' = {
  name: 'virtualNetwork'
  parent: funcApp
  properties: {
    subnetResourceId: funcSubnetId
    swiftSupported: true   // enables regional (not legacy gateway) VNet integration
  }
}
```

---

### 4. Keyless storage (`allowSharedKeyAccess=false`)

Use the `AzureWebJobsStorage__` double-underscore format (Functions v4 identity-based connections):

```bicep
{ name: 'AzureWebJobsStorage__accountName', value: funcStorageAccountName }
{ name: 'AzureWebJobsStorage__credential',  value: 'managedidentity' }
```

RBAC required on the function storage account:
- `Storage Blob Data Owner` (b7e6dc6d-…)
- `Storage Account Contributor` (17d1049b-…)
- _Optional:_ `Storage Queue Data Contributor` + `Storage Table Data Contributor` if runtime state errors appear

---

### 5. Role assignment `name` gotcha (BCP120)

`funcApp.identity.principalId` is NOT known at deployment start. Using it in `name: guid(...)` triggers BCP120. Fix:

```bicep
// ❌ BCP120 — principalId not computable at start
name: guid(keyVault.id, funcApp.identity.principalId, roleDefId)

// ✅ Correct — funcApp.id is deterministic at plan time
name: guid(keyVault.id, funcApp.id, roleDefId)
// principalId is still correct in properties:
properties: { principalId: funcApp.identity.principalId, ... }
```

---

### 6. Private DNS zones needed (add to `private-dns.bicep`)

| Zone | Sub-resource | Notes |
|---|---|---|
| `privatelink.azurewebsites.net` | `sites` (inbound PE) | `#disable-next-line no-hardcoded-env-urls` |
| `privatelink.file.core.windows.net` | `file` (func storage) | `#disable-next-line no-hardcoded-env-urls` |
| `privatelink.blob.core.windows.net` | `blob` (func storage) | Already exists in this lab |

All zones linked to **both** VNets (east + west) with `location: 'global'`.

---

### 7. Deployment note

`publicNetworkAccess=Disabled` blocks the SCM/Kudu endpoint from the public internet.  
To deploy function code, either:
- Use a jump VM or Azure Bastion on the VNet, then `az functionapp deployment source config-zip`
- Temporarily enable SCM public access for the deploy, then disable it again
- Use a self-hosted GitHub Actions runner on the VNet

---

### 8. `main.bicep` wiring (conditional on `deployFunctionApp bool = true`)

```bicep
module funcApp 'modules/funcapp.bicep' = if (deployFunctionApp) { ... }
module funcAppPrivateEndpoint 'modules/private-endpoint.bicep' = if (deployFunctionApp) {
  params: { groupId: 'sites', privateDnsZoneId: privateDns.outputs.websitesZoneId }
}
module funcStorageBlobPrivateEndpoint ... = if (deployFunctionApp) {
  params: { groupId: 'blob', privateDnsZoneId: privateDns.outputs.blobZoneId }
}
module funcStorageFilePrivateEndpoint ... = if (deployFunctionApp) {
  params: { groupId: 'file', privateDnsZoneId: privateDns.outputs.fileZoneId }
}
```
