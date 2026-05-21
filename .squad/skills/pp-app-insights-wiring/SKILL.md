# Skill: PP Application Insights Wiring

**Applies to:** Power Platform Managed Environments, workspace-based Application Insights  
**Authored:** 2026-05-20T15:36:31-05:00 by Tank

---

## Pattern: Binding Application Insights to a Power Platform Managed Environment

### Overview

Power Platform Managed Environments support an environment-level Application
Insights binding. When set, all connector invocations, canvas app traces, and
Power Automate flow telemetry are forwarded to the bound resource. Pairing this
with a **workspace-based** App Insights resource (linked to a Log Analytics
workspace) allows cross-resource KQL queries that correlate PP telemetry with
Azure resource diagnostics (Key Vault AuditEvent, private-endpoint metrics).

---

### Bicep: workspace-based App Insights module

```bicep
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'                    // Required for PP
    WorkspaceResourceId: logAnalyticsWorkspaceId  // Links to LAW
    IngestionMode: 'LogAnalytics'              // Workspace-based
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}
```

Required outputs: `appInsightsResourceId`, `appInsightsConnectionString`,
`appInsightsInstrumentationKey`.

---

### PowerShell: binding the environment via BAP REST API

`Set-AdminPowerAppEnvironmentApplicationInsights` does **not** exist in
`Microsoft.PowerPlatform.EnterprisePolicies` v0.17.0 or
`Microsoft.PowerApps.Administration.PowerShell`. Use the REST API directly.

#### 1. Acquire token

```powershell
$ppTokenResult = az account get-access-token --resource 'https://service.powerapps.com/' --output json | ConvertFrom-Json
$token = $ppTokenResult.accessToken
```

#### 2. Idempotency check

```powershell
$envUri = "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments/$EnvironmentId?api-version=2023-06-01"
$headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }
$currentEnv = Invoke-RestMethod -Uri $envUri -Method Get -Headers $headers
$currentAiId = [string]$currentEnv.properties.applicationInsightsId
if ($currentAiId -ieq $desiredAppInsightsResourceId) { return }  # already set
```

#### 3. PATCH to bind

```powershell
$body = @{
    properties = @{
        applicationInsightsId  = $desiredAppInsightsResourceId
        applicationInsightsKey = $appInsightsConnectionString  # prefer connection string
    }
} | ConvertTo-Json -Depth 5 -Compress

Invoke-RestMethod -Uri $envUri -Method Patch -Headers $headers -Body $body
```

**Notes:**
- `applicationInsightsKey` accepts either the instrumentation key (legacy) or
  the connection string. Use the **connection string** for workspace-based
  resources (it encodes the ingestion endpoint and is more resilient).
- AI binding replacement (overwriting an existing binding) is safe — unlike
  enterprise policy swaps, it does not affect subnet routing.
- API version `2023-06-01` confirmed working as of 2026-05-20.

---

### What is NOT automatable

| Step | Reason |
|---|---|
| Tenant-level analytics (PPAC) | Admin center UI only |
| Custom connector "Enable diagnostics" | Per-connector; make.powerapps.com UI |
| Canvas app republish | Maker action; app must be republished to pick up new AI binding |

---

### Related files

- `infra/modules/appInsights.bicep`
- `infra/main.bicep` (module invocation + outputs)
- `scripts/02-configure-pp-vnet.ps1` (binding step after Enable-SubnetInjection)
- `scripts/04-enable-connector-telemetry.ps1` (verification + KQL guidance)
- `.squad/decisions/inbox/tank-pp-monitoring.md`
- `docs/monitoring.md` (Niobe — full KQL library, alert rules, dashboard)
