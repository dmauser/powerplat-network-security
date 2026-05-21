# Decision: West VNet Flow Logs — VNet-level resource type chosen

**Date:** 2026-05-21T16:38:49-05:00
**Author:** Trinity (IaC)
**Status:** Confirmed (already in main)

## Context

Task required enabling VNet flow logs for `vnet-pbinet-dev-west` (westus) using the same Log Analytics workspace (`law-pbinet-dev-k6ozyjremes6m`) already used by the east VNet flow log. The instruction was to match whatever pattern was already established — not introduce a new one.

## Decision

Use **`Microsoft.Network/networkWatchers/flowLogs@2024-05-01`** (VNet-level flow logs), NOT legacy NSG flow logs.

This was already the established pattern for the east VNet (`flowLogEast` in `infra/main.bicep`). The `targetResourceId` property is set to the VNet resource ID directly, enabling flow capture at the VNet boundary rather than per-NSG. This is the current recommended approach per Microsoft Network Watcher documentation.

## Why not NSG flow logs?

NSG flow logs (`Microsoft.Network/networkSecurityGroups/providers/flowLogs`) are the legacy mechanism. They require an NSG on each subnet and must be enabled per-NSG — more objects to manage. VNet flow logs cover all traffic through the VNet in a single resource, which is simpler and the documented successor.

## Implementation

- Module: `infra/modules/flow-logs.bicep` (shared, parameterized by region)
- Wire-up: `infra/main.bicep`, module `flowLogWest`
  - `scope: resourceGroup('NetworkWatcherRG')`
  - `networkWatcherName: 'NetworkWatcher_${regionB}'` (westus)
  - `location: regionB`
  - `vnetId: network.outputs.vnetWestId`
  - `logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId` (shared LAW)
  - `storageAccountId: flowLogsStorage.outputs.storageAccountId` (shared storage)
- Both `az bicep build` and `az bicep lint` exit 0.

## Future extension

To add flow logs for a third region: copy the `flowLogWest` block, set `location`, `flowLogName`, `vnetId`, and `networkWatcherName` for the new region. The module itself does not need changes.
