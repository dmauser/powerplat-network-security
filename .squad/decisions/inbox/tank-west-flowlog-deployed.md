# tank-west-flowlog-deployed.md
<!-- Decision inbox entry for Scribe / record-keeping -->

**From:** Tank  
**Date:** 2026-05-21T17:55:00-05:00  
**For:** Scribe (record), Morpheus (arch confirmation)

---

## Summary

West VNet flow log (`fl-vnet-pbinet-dev-west`) is **deployed and enabled** in `NetworkWatcherRG`. Both east and west flow logs are now active and writing to Log Analytics.

---

## What was deployed

| Resource | Name | RG | Region | Status |
|---|---|---|---|---|
| West flow-logs storage account | `stpbinetfldevwiqxkvrtksy` | `NetworkWatcherRG` | `westus` | ✅ Succeeded |
| West VNet flow log | `fl-vnet-pbinet-dev-west` | `NetworkWatcherRG` | `westus` | ✅ Enabled |

---

## Root cause of original failure

`infra/main.bicep` was passing the **east** storage account (`stpbinetfldevk6ozyjremes`, `eastus`) to the west flow log module. Azure requires the storage account to be co-located with the Network Watcher region (`westus`). ARM error: `InvalidStorageAccountLocation`.

**Fix committed:** `main.bicep` now deploys a second `flowLogsStorageWest` module (scoped to `NetworkWatcherRG`, location `westus`) and passes its output to `flowLogWest`. The west storage account name is generated via `uniqueString(resourceGroup().id)` where the RG is `NetworkWatcherRG` — different hash from the east account, no name collision.

---

## Commands used

### Step 1 — West flow-logs storage (westus, scoped to NetworkWatcherRG)

```bash
az deployment group create \
  --name flowlogs-stg-west-202605211751 \
  --resource-group NetworkWatcherRG \
  --template-file infra/modules/flow-logs-storage.bicep \
  --parameters "@.azure/flowlogs-stg-west-params.json"
```

Output:
```json
{
  "storageAccountId": "/subscriptions/43d55e51-58fe-486f-9e2a-ba56b8dd15de/resourceGroups/NetworkWatcherRG/providers/Microsoft.Storage/storageAccounts/stpbinetfldevwiqxkvrtksy",
  "storageAccountName": "stpbinetfldevwiqxkvrtksy"
}
```

### Step 2 — West flow log (targeting vnet-pbinet-dev-west, NetworkWatcher_westus)

```bash
az deployment group create \
  --name flowlog-west-202605211753 \
  --resource-group NetworkWatcherRG \
  --template-file infra/modules/flow-logs.bicep \
  --parameters "@.azure/flowlog-west-params.json"
```

Key parameters:
- `location`: `westus`
- `flowLogName`: `fl-vnet-pbinet-dev-west`
- `vnetId`: `.../vnet-pbinet-dev-west`
- `storageAccountId`: `.../stpbinetfldevwiqxkvrtksy` (westus — new)
- `logAnalyticsWorkspaceId`: `.../law-pbinet-dev-k6ozyjremes6m` (eastus LAW — cross-region is fine for TA)
- `logAnalyticsWorkspaceRegion`: `eastus`
- `logAnalyticsWorkspaceGuid`: `9392a56e-0e4c-41f7-bd0c-829b94972d42`
- `networkWatcherName`: `NetworkWatcher_westus`

---

## Verification output

### `az network watcher flow-log list --location westus`

```
Enabled  Location  Name                     ProvisioningState  StorageId
-------  --------  -----------------------  -----------------  ----------------------------------------
True     westus    fl-vnet-pbinet-dev-west  Succeeded          .../stpbinetfldevwiqxkvrtksy
```
Target VNet GUID: `74e9ffd9-6e68-4320-ae8d-1b734d1bea43` (`vnet-pbinet-dev-west`)

### `az network watcher flow-log list --location eastus`

```
Enabled  Location  Name                     ProvisioningState  StorageId
-------  --------  -----------------------  -----------------  ----------------------------------------
True     eastus    fl-vnet-pbinet-dev-east  Succeeded          .../stpbinetfldevk6ozyjremes
```
Target VNet GUID: `e8cbf9cb-bf2c-4691-b866-a3b53599b149` (`vnet-pbinet-dev-east`)

Both flow logs: **Enabled = True, ProvisioningState = Succeeded.**

---

## Bicep fix committed

`infra/main.bicep` updated — `flowLogsStorageWest` module added, `flowLogWest.storageAccountId` now correctly references west storage. Safe for future `az deployment sub create` runs.
