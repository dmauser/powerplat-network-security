# Decision: funcapp.bicep module shape + integration points

**Date:** 2026-05-21  
**Author:** Trinity (Infra Engineer)  
**Status:** Ready for Tank handover

---

## Summary

`infra/modules/funcapp.bicep` (resource-group scoped) is now the canonical IaC for the Part 4 demo Function App. This note documents the module shape, integration points, and what Tank needs to do next.

---

## What was deployed (Bicep only — not yet `az deployment sub create`)

### New module: `infra/modules/funcapp.bicep`
- **Function storage account:** `st{prefix}{env}func{uniqueString(rg.id)}` — `publicNetworkAccess=Disabled`, `allowSharedKeyAccess=false`, Standard_LRS
- **App Service Plan:** `asp-{prefix}-{env}-func`, EP1 Elastic Premium, Linux, `reserved=true`
- **Function App:** `func-{prefix}-{env}`, kind `functionapp,linux`, PowerShell 7.4 (`linuxFxVersion=PowerShell|7.4`), system-assigned MI
- **VNet integration:** `Microsoft.Web/sites/networkConfig` with `name: 'virtualNetwork'`, `swiftSupported: true`, integrated into `snet-funcapp` (param `funcSubnetId`)
- **`publicNetworkAccess: 'Disabled'`** on Function App — inbound traffic only via private endpoint
- **`vnetRouteAllEnabled: true`** — all outbound DNS resolves through the VNet (reaches private endpoints for KV + storage)

### App Settings wired
| Setting | Value |
|---|---|
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | from `existing` `appi-{prefix}-{env}` reference |
| `KEY_VAULT_NAME` | passed as param |
| `SECRET_NAME` | `demo-secret` |
| `FUNCTIONS_WORKER_RUNTIME` | `powershell` |
| `FUNCTIONS_EXTENSION_VERSION` | `~4` |
| `WEBSITE_RUN_FROM_PACKAGE` | `1` (Tank sets actual zip) |
| `AzureWebJobsStorage__accountName` | function storage account name |
| `AzureWebJobsStorage__credential` | `managedidentity` |

### RBAC granted
| Role | Scope |
|---|---|
| Key Vault Secrets User | existing demo KV (`existing` ref — KV not redeployed) |
| Storage Blob Data Owner | function storage account |
| Storage Account Contributor | function storage account |

> **Note for Tank:** If you see runtime errors about queue/table operations, also assign Storage Queue Data Contributor + Storage Table Data Contributor on the function storage account. These are sometimes needed for Functions v4 internal state.

### Networking additions (in other modules)
| Resource | Module | Detail |
|---|---|---|
| `snet-funcapp` subnet | `network.bicep` | `10.10.2.0/27`, East VNet, delegated `Microsoft.Web/serverFarms` |
| PE for Function App inbound | `main.bicep` (pe-func-*) | `sites` group, `snet-pep`, `privatelink.azurewebsites.net` zone |
| PE for func storage blob | `main.bicep` (pe-funcstg-blob-*) | `blob` group, `snet-pep`, reuses `privatelink.blob.core.windows.net` zone |
| PE for func storage file | `main.bicep` (pe-funcstg-file-*) | `file` group, `snet-pep`, `privatelink.file.core.windows.net` zone |
| `privatelink.azurewebsites.net` zone | `private-dns.bicep` | linked to vnetEast + vnetWest |
| `privatelink.file.core.windows.net` zone | `private-dns.bicep` | linked to vnetEast + vnetWest |

### main.bicep params added
- `deployFunctionApp bool = true` — set `false` to skip the entire Part 4 stack
- `infra/parameters/dev.parameters.json` has `deployFunctionApp: true`

### main.bicep outputs added
- `functionAppName` — the deployed Function App resource name
- `functionAppHostname` — the private hostname (Tank needs this to call the HTTP trigger from inside the VNet)
- `funcSubnetId` — the snet-funcapp subnet resource ID

---

## Tank's handover checklist

1. **Deploy:** run `scripts/01-deploy.sh` (or `az deployment sub create`) — `deployFunctionApp=true` is the default.
2. **Build function code:** PowerShell 7.4 HTTP trigger that:
   - Uses `$env:KEY_VAULT_NAME` + `$env:SECRET_NAME` to call Key Vault via `Az.KeyVault`
   - Emits custom App Insights dependency telemetry (confirm `APPLICATIONINSIGHTS_CONNECTION_STRING` is picked up automatically by the App Insights SDK)
3. **Deploy function zip:** `az functionapp deployment source config-zip --src <path-to-func.zip> ...`  
   ⚠️ `publicNetworkAccess=Disabled` blocks the SCM endpoint from the public internet. Deploy from a jump host on the VNet, or temporarily re-enable public SCM access and lock it down again after deploy.
4. **Test:** call the HTTP trigger from inside the VNet. Verify App Insights shows the Key Vault dependency call with correct target + success/failure.
5. **Verify DNS resolution:** from inside the VNet, `Resolve-DnsName func-pbinet-dev.azurewebsites.net` should return a `10.10.1.x` IP (snet-pep). `Resolve-DnsName kv-pbinet-dev-<suffix>.vault.azure.net` should also resolve to PE IP.

---

## Module params reference (for main.bicep wiring)

```bicep
module funcApp 'modules/funcapp.bicep' = if (deployFunctionApp) {
  name: 'funcapp-${prefix}-${env}'
  scope: rg
  params: {
    prefix: prefix
    env: env
    location: defaultLocation
    tags: tags
    funcSubnetId: network.outputs.subnetEastFuncAppId
    appInsightsName: appInsights.outputs.appInsightsName
    keyVaultName: keyVault.outputs.keyVaultName
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
  }
}
```
