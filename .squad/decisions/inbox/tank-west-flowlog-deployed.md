# tank-west-flowlog-deployed.md
<!-- Decision inbox entry for Scribe / record-keeping -->

**From:** Tank  
**Date:** 2026-05-21T18:15:00-05:00  
**For:** Scribe (record), Morpheus (arch confirmation), dmauser (RG layout confirmation)

---

## Summary

West VNet flow log is **deployed, enabled, and fully inside `rg-pbinet-dev-eastus`** per directive.
`NetworkWatcher_westus` and its flow-log child were moved from `NetworkWatcherRG` to `rg-pbinet-dev-eastus` via `az resource move`.

---

## Final resource placement

| Resource | Name | RG | Region | Status |
|---|---|---|---|---|
| Network Watcher (west) | `NetworkWatcher_westus` | `rg-pbinet-dev-eastus` | `westus` | ✅ Succeeded |
| Flow-logs storage (west) | `stpbinetfldevwiqxkvrtksy` | `rg-pbinet-dev-eastus` | `westus` | ✅ Moved |
| VNet flow log (west) | `fl-vnet-pbinet-dev-west` | `rg-pbinet-dev-eastus` | `westus` | ✅ Enabled |
| Network Watcher (east) | `NetworkWatcher_eastus` | `NetworkWatcherRG` | `eastus` | ⚠️ Flagged — still in NetworkWatcherRG |
| VNet flow log (east) | `fl-vnet-pbinet-dev-east` | `NetworkWatcherRG` | `eastus` | ⚠️ Flagged — still in NetworkWatcherRG |

---

## Platform constraint discovered (and resolved for west)

`az network watcher configure -g rg-pbinet-dev-eastus --locations westus` silently returned
the existing `NetworkWatcherRG`-hosted watcher — it does NOT re-create the watcher in a
different RG when one already exists for that region. Azure enforces one watcher per region
per subscription.

**Resolution used:** `az resource move` — this DOES support moving `Microsoft.Network/networkWatchers`
between resource groups within the same subscription. The child flow log resource moved automatically
with the parent watcher. The west flow-logs storage account was moved separately in the same call.

After the move, the flow log's `storageId` still referenced the old `NetworkWatcherRG` path.
A second `az deployment group create` (scoped to `rg-pbinet-dev-eastus`) corrected the reference.

---

## Commands executed (in order)

### 1 — West flow-logs storage (initial deploy into NetworkWatcherRG — pre-directive)
```bash
az deployment group create \
  --name flowlogs-stg-west-202605211751 \
  --resource-group NetworkWatcherRG \
  --template-file infra/modules/flow-logs-storage.bicep \
  --parameters "@.azure/flowlogs-stg-west-params.json"
# Output: stpbinetfldevwiqxkvrtksy (westus)
```

### 2 — West flow log (initial deploy into NetworkWatcherRG — pre-directive)
```bash
az deployment group create \
  --name flowlog-west-202605211753 \
  --resource-group NetworkWatcherRG \
  --template-file infra/modules/flow-logs.bicep \
  --parameters "@.azure/flowlog-west-params.json"
```

### 3 — Move watcher + storage to rg-pbinet-dev-eastus (per directive)
```bash
az resource move \
  --destination-group rg-pbinet-dev-eastus \
  --ids \
    /subscriptions/43d55e51.../NetworkWatcherRG/.../networkWatchers/NetworkWatcher_westus \
    /subscriptions/43d55e51.../NetworkWatcherRG/.../storageAccounts/stpbinetfldevwiqxkvrtksy
# Exit 0 — both resources moved, child flow log moved with parent watcher
```

### 4 — Fix storageId reference after move
```bash
az deployment group create \
  --name flowlog-west-fix-202605211810 \
  --resource-group rg-pbinet-dev-eastus \
  --template-file infra/modules/flow-logs.bicep \
  --parameters "@.azure/flowlog-west-params.json"
# storageId now: .../rg-pbinet-dev-eastus/.../stpbinetfldevwiqxkvrtksy
```

---

## Verification output

```
az network watcher flow-log list --location westus

Enabled  RG                    Name                     State      Storage
True     rg-pbinet-dev-eastus  fl-vnet-pbinet-dev-west  Succeeded  .../rg-pbinet-dev-eastus/.../stpbinetfldevwiqxkvrtksy

az network watcher flow-log list --location eastus

Enabled  RG                Name                     State
True     NetworkWatcherRG  fl-vnet-pbinet-dev-east  Succeeded
```

---

## East flow log / watcher — migration flag

`NetworkWatcher_eastus` and `fl-vnet-pbinet-dev-east` are still in `NetworkWatcherRG`.
Same `az resource move` pattern applies when Damião wants to consolidate:

```bash
EAST_WATCHER_ID=".../NetworkWatcherRG/.../networkWatchers/NetworkWatcher_eastus"
EAST_STORAGE_ID=".../rg-pbinet-dev-eastus/.../storageAccounts/stpbinetfldevk6ozyjremes"
# Note: east storage is ALREADY in rg-pbinet-dev-eastus — only the watcher needs moving.
az resource move \
  --destination-group rg-pbinet-dev-eastus \
  --ids $EAST_WATCHER_ID
# Then re-deploy flowlog-east scoped to rg instead of resourceGroup('NetworkWatcherRG')
```

The east storage account `stpbinetfldevk6ozyjremes` is already in `rg-pbinet-dev-eastus`
(it was deployed there from the start). Only the watcher + flow log need to move.

---

## Bicep change committed

`infra/main.bicep`:
- `flowLogsStorageWest` scope changed from `resourceGroup('NetworkWatcherRG')` → `rg`
- `flowLogWest` scope changed from `resourceGroup('NetworkWatcherRG')` → `rg`
- `flowLogEast` scope left as `resourceGroup('NetworkWatcherRG')` with TODO comment
- Inline comments document the RG migration history
