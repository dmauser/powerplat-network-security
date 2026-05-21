# Skill: Bicep Diagnostic-Settings Fan-Out

**Applies to:** Any Azure PaaS resource where you need `Microsoft.Insights/diagnosticSettings`
**Authored:** 2026-05-20T15:36:31-05:00 by Trinity

---

## Problem

Bicep extension-resource `scope` must be a statically-typed resource symbolic name — you cannot write `scope: any(someResourceIdString)`. This makes a truly generic, reusable diagnostic-settings module impossible using standard Bicep syntax.

## Solution: nested ARM deployment as escape hatch

In ARM JSON, `Microsoft.Insights/diagnosticSettings` accepts a dynamic `scope` string. By embedding the diagnostic-settings resource inside a `Microsoft.Resources/deployments` inline template, you get the dynamic scope you need. The outer Bicep module passes the target resource ID as a parameter; the inner ARM template resolves it at deploy time.

### Module signature (`infra/modules/diagnosticSettings.bicep`)

```bicep
@description('Full ARM resource ID of the target resource.')
param targetResourceId string

@description('Resource ID of the Log Analytics workspace.')
param workspaceId string

@description('Name of the diagnostic setting (must be unique per target resource).')
param settingName string = 'default-diagnostics'

@description('Log categories. Each item: { category: string, enabled: bool }')
param logs array = []

@description('Metric categories. Each item: { category: string, enabled: bool }')
param metrics array = []
```

### Call shape (from main.bicep)

```bicep
module diagKv 'modules/diagnosticSettings.bicep' = {
  name: 'diag-kv-${prefix}-${env}'
  scope: rg
  params: {
    targetResourceId: keyVault.outputs.keyVaultId
    workspaceId:      logAnalytics.outputs.workspaceId
    settingName:      'diag-kv'
    logs: [
      { category: 'AuditEvent', enabled: true }
    ]
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}
```

### Key implementation details

```bicep
// Suppress the lint rule — nested deployment is the intentional workaround here.
#disable-next-line no-deployments-resources
resource innerDeployment 'Microsoft.Resources/deployments@2022-09-01' = {
  name: 'diag-${uniqueString(targetResourceId, settingName)}'
  properties: {
    mode: 'Incremental'
    expressionEvaluationOptions: { scope: 'inner' }
    parameters: {
      targetResourceId: { value: targetResourceId }
      workspaceId:      { value: workspaceId }
      settingName:      { value: settingName }
      logs:             { value: logs }
      metrics:          { value: metrics }
    }
    template: {
      '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        targetResourceId: { type: 'string' }
        workspaceId:      { type: 'string' }
        settingName:      { type: 'string' }
        logs:             { type: 'array' }
        metrics:          { type: 'array' }
      }
      resources: [
        {
          type: 'Microsoft.Insights/diagnosticSettings'
          apiVersion: '2021-05-01-preview'
          // ARM evaluates '[parameters(...)]' expressions at deploy time.
          // Bicep treats these as plain string literals — no conflict.
          scope: '[parameters(\'targetResourceId\')]'
          name:  '[parameters(\'settingName\')]'
          properties: {
            workspaceId: '[parameters(\'workspaceId\')]'
            logs:        '[parameters(\'logs\')]'
            metrics:     '[parameters(\'metrics\')]'
          }
        }
      ]
    }
  }
}
```

**Why `'[parameters(\'targetResourceId\')]'` works:**
- Bicep string: the `\'` escape produces a literal `'`, so the value is `[parameters('targetResourceId')]`.
- ARM evaluates any property string starting with `[` and ending with `]` as a template expression.
- With `expressionEvaluationOptions.scope=inner`, expressions are resolved in the nested template's own parameter context. ✓

---

## Resource-specific log categories reference

| Resource type | Log categories | Metric categories |
|---|---|---|
| `Microsoft.KeyVault/vaults` | `AuditEvent`, `AzurePolicyEvaluationDetails` | `AllMetrics` |
| `Microsoft.Storage/storageAccounts/blobServices` | `StorageRead`, `StorageWrite`, `StorageDelete` | `Transaction` |
| `Microsoft.Sql/servers/databases` | `SQLSecurityAuditEvents`, `Errors`, `Timeouts` | `Basic`, `InstanceAndAppAdvanced` |
| `Microsoft.Network/privateEndpoints` | _(none — no log categories exist for PEs)_ | `AllMetrics` |
| `Microsoft.Network/virtualNetworks` | _(none)_ | `AllMetrics` |

**Storage note:** always target `{storageAccountId}/blobServices/default` for blob operation logs — diagnostics for read/write/delete must be applied to the blob service child resource, not the storage account root.

**SQL note:** target the **database** resource ID (`{serverId}/databases/{dbName}`), not the server. Server-level diagnostics and database-level diagnostics are separate.

---

## Lint suppression

The `no-deployments-resources` Bicep lint rule fires when `Microsoft.Resources/deployments` is declared as a resource rather than a module. This is expected here and is the documented suppression pattern:

```bicep
#disable-next-line no-deployments-resources
resource innerDeployment 'Microsoft.Resources/deployments@2022-09-01' = { ... }
```

After suppression, `az bicep build` and `az bicep lint` both exit 0 with zero warnings.

---

## Deployment name uniqueness

The nested deployment name uses `uniqueString(targetResourceId, settingName)` (13 hex chars, prefixed with `diag-`, total 18 chars). This guarantees uniqueness per target+setting combination within the resource group and stays well under the 64-char limit.

---

## Related

- `infra/modules/diagnosticSettings.bicep`
- `infra/modules/logAnalytics.bicep`
- `infra/main.bicep` (fan-out wiring for 8 targets)
- `.squad/decisions/inbox/trinity-monitoring-plumbing.md`
- `.squad/skills/bicep-private-endpoint-acl-hardening/SKILL.md`
