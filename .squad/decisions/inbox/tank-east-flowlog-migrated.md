# East Flow Log + Watcher Migration Complete

**Date:** 2026-05-21  
**Commit:** faeeab1  
**Author:** Tank (infra)

## What was done

Migrated `NetworkWatcher_eastus` and its child `fl-vnet-pbinet-dev-east` from `NetworkWatcherRG`
→ `rg-pbinet-dev-eastus` using `az resource move`. This completes the single-RG directive:
all lab resources now live in `rg-pbinet-dev-eastus`.

## Steps executed

```powershell
# 1. Move watcher (child flow log moves automatically)
$eastWatcherId = "/subscriptions/43d55e51-58fe-486f-9e2a-ba56b8dd15de/resourceGroups/NetworkWatcherRG/providers/Microsoft.Network/networkWatchers/NetworkWatcher_eastus"
az resource move --destination-group rg-pbinet-dev-eastus --ids $eastWatcherId

# 2. Re-deploy flow log to fix storageId (not auto-updated after move)
az deployment group create \
  --resource-group rg-pbinet-dev-eastus \
  --template-file infra/modules/flow-logs.bicep \
  --parameters "@infra/east-flowlog-params.json"
```

## Verification

```
NetworkWatcher_eastus   rg-pbinet-dev-eastus  Succeeded
NetworkWatcher_westus   rg-pbinet-dev-eastus  Succeeded

fl-vnet-pbinet-dev-east  Enabled  Succeeded
  storageId: .../rg-pbinet-dev-eastus/.../stpbinetfldevk6ozyjremes  ✓

fl-vnet-pbinet-dev-west  Enabled  Succeeded
  storageId: .../rg-pbinet-dev-eastus/.../stpbinetfldevwiqxkvrtksy  ✓
```

## Bicep state

`infra/main.bicep`:
- `flowLogEast` scope: `resourceGroup('NetworkWatcherRG')` → `rg`  
- TODO comment removed  
- East and west modules are now symmetric

## Known drift: uniqueString collision for west storage

`flow-logs-storage.bicep` uses `uniqueString(resourceGroup().id)`. With both east and west
storage modules scoped to `rg-pbinet-dev-eastus`, they produce the same hash. The live west
storage (`stpbinetfldevwiqxkvrtksy`) was created when scoped to `NetworkWatcherRG` and has a
different name than what Bicep generates scoped to `rg`. A clean re-deploy would create a
new storage account and leave the old one behind.

**Resolution needed (future):** Parameterize west storage account name in `main.bicep`,
or use `location` as part of the `uniqueString` seed in `flow-logs-storage.bicep`.

## Remaining blockers

- Function app live deploy blocked: MCAP subscription `MngEnvMCAP423074` has `Total VMs: 0`
  quota for all App Service Plan SKUs (EP1, B1, S1, P1v2). Consumption (Y1) cannot be used
  because it lacks regional VNet integration. Blocked until quota is available.
