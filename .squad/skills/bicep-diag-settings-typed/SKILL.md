# Skill: Bicep Diagnostic Settings — Typed Inline Resources

**Applies to:** Bicep v0.17+ (confirmed broken pattern in Bicep v0.42.x)

---

## Problem: Generic `diagnosticSettings.bicep` via Nested ARM is Broken

The common pattern of writing a reusable `diagnosticSettings.bicep` that uses a `Microsoft.Resources/deployments` inner template to attach `Microsoft.Insights/diagnosticSettings` to any resource type **does not work in Bicep**.

### Why it fails

Bicep auto-escapes `[` → `[[` in every string value that appears in a Bicep object literal or in a variable populated by `loadJsonContent()`. At ARM template compile time, the string `[parameters('targetResourceId')]` becomes `[[parameters('targetResourceId')]` — a literal string, not an ARM expression. The ARM engine never evaluates it as an expression, and the diagnostic settings resource ends up with `scope = "[parameters('targetResourceId')]"` — an invalid resource ID.

**This affects both approaches:**
- Inline object literals with ARM expression strings in Bicep: escaped
- `loadJsonContent('inner.json')`: Bicep stores the result in a `$fxv#0` variable and still applies escaping

There is currently no way to inject unescaped ARM expressions into a Bicep-compiled deployment template string.

---

## Correct Pattern: Typed Inline Resource Declarations with `scope:`

Attach diagnostic settings directly in each resource module using a properly typed Bicep resource declaration with the `scope` property referencing the co-deployed resource:

```bicep
// In keyvault.bicep — after the Key Vault resource declaration

param logAnalyticsWorkspaceId string = ''   // empty = skip

resource kvDiagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: 'diag-${keyVaultName}'
  scope: keyVault   // <-- Bicep symbolic reference, fully typed
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { category: 'AuditEvent', enabled: true }
      { category: 'AzurePolicyEvaluationDetails', enabled: true }
    ]
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}
```

**Key rules:**
- `scope:` must reference a Bicep symbolic name for a resource in the same file (or a `existing` resource reference)
- Use `if (!empty(logAnalyticsWorkspaceId))` to make the diag settings opt-out when no workspace is provided
- The resource variable (e.g. `keyVault`) must be declared before the diagnostic settings resource
- Do NOT use `parent:` for diagnostic settings — use `scope:` (diagnostic settings are extension resources, not child resources)

---

## Resource Types That Do NOT Support Diagnostic Settings

Azure API returns `ResourceTypeNotSupported` for:

- `microsoft.network/privateendpoints` — NO diag settings. Monitor via Azure Monitor Metrics blade (`PEConnectionsConnected`, `PEBytesIn`, `PEBytesOut`). Metric alert rules on PE resource IDs work fine; only diag-settings emit is unsupported.

Always test new resource types by checking: [https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/resource-logs-categories](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/resource-logs-categories)

---

## Modules Using This Pattern in This Repo

| Module | Resource scoped | Log categories | Metrics |
|---|---|---|---|
| `infra/modules/keyvault.bicep` | `keyVault` (Key Vault) | AuditEvent, AzurePolicyEvaluationDetails | AllMetrics |
| `infra/modules/storage.bicep` | `blobService` (Blob service child) | StorageRead, StorageWrite, StorageDelete | Transaction |
| `infra/modules/sql.bicep` | `sqlDb` (SQL Database) | SQLSecurityAuditEvents, Errors, Timeouts, Basic, InstanceAndAppAdvanced | AllMetrics |
| `infra/modules/network.bicep` | `vnetEast`, `vnetWest` (VNets) | _(none — VNets have no log categories)_ | AllMetrics |
| `infra/modules/private-endpoint.bicep` | _(none — not supported)_ | — | — |

---

## `diagnosticSettings.bicep` Status

`infra/modules/diagnosticSettings.bicep` — kept in repo as documentation of the broken nested-ARM pattern. Not referenced by `main.bicep`. The module header contains a comment block explaining the Bicep escaping issue. Do not use this module for new work.

`infra/modules/diagnosticSettings-inner.json` — intermediate artifact from a `loadJsonContent()` workaround attempt that also failed. Safe to delete.
