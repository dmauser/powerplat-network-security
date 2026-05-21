# Skill: PP Enterprise Policy Link — BAP REST Bypass

**Category:** Power Platform Administration  
**Author:** Tank  
**Date:** 2026-05-20  
**Reusability:** Any lab or automation that needs to link a Managed Environment to a NetworkInjection enterprise policy without depending on the `Microsoft.PowerPlatform.EnterprisePolicies` PowerShell module.

---

## Problem

The `Enable-SubnetInjection` cmdlet in `Microsoft.PowerPlatform.EnterprisePolicies` v0.17.0 calls `Get-AzAccessToken -ResourceUrl 'https://api.powerplatform.com/'` internally. When the Az PowerShell session was bridged via `Connect-AzAccount -AccessToken` (the ARM token bridge), this call fails with:

```
[AccessTokenAuthenticator] failed to retrieve access token for resource 'https://api.powerplatform.com/'
```

The module falls through to interactive browser auth, hanging in non-interactive shells.

---

## Solution: Direct BAP REST

The BAP REST API (`api.bap.microsoft.com`) supports the same enterprise policy link operation. It authenticates with `service.powerapps.com` tokens, which `az account get-access-token` CAN acquire non-interactively using the current az CLI session.

### Step 0 — Ensure governance tier is Standard (PREREQUISITE)

Default PP environments start with `protectionLevel: "Basic"`. This blocks `NewNetworkInjection`
with `400 InvalidLifecycleOperationRequest: ... governance configuration`. Check and upgrade
before attempting the link.

```powershell
# Install once; v2.0.217+ required
Install-Module Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser -AllowClobber -Force

Import-Module Microsoft.PowerApps.Administration.PowerShell
Add-PowerAppsAccount   # uses ambient cached credentials; no -AccessToken parameter in v2.0.217

$envId = "Default-<tenantId>"

# Check current tier
$env = Get-AdminPowerAppEnvironment -EnvironmentName $envId
$tier = $env.Internal.properties.governanceConfiguration.protectionLevel
Write-Host "Current protectionLevel: $tier"

if ($tier -ne 'Standard') {
    Set-AdminPowerAppEnvironmentGovernanceConfiguration `
        -EnvironmentName $envId `
        -UpdatedGovernanceConfiguration @{ protectionLevel = "Standard" }
    # Returns 202 Accepted; waits for EnableGovernanceConfiguration lifecycle op to Succeed (~30-60s)
    Write-Host "Governance tier upgraded to Standard. Waiting 60s for propagation..."
    Start-Sleep -Seconds 60
}
```

**Key constraint:** Direct PATCH to `scopes/admin/environments` with `protectionLevel: "Standard"`
returns 204 but silently makes NO change. Only the dedicated `governanceConfiguration` endpoint
(called by `Set-AdminPowerAppEnvironmentGovernanceConfiguration`) actually upgrades the tier.

---

### Step 1 — Acquire BAP token

```powershell
$token = (az account get-access-token --resource 'https://service.powerapps.com/' --output json | ConvertFrom-Json).accessToken
```

### Step 2 — Resolve EP systemId (NOT the ARM ID)

The link body requires `properties.systemId` from the ARM resource, NOT the ARM resource ID itself.

```powershell
$epArmId = "/subscriptions/<subId>/resourceGroups/<rg>/providers/Microsoft.PowerPlatform/enterprisePolicies/<name>"
$epSystemId = (az resource show --ids $epArmId --api-version 2020-10-30-preview --query "properties.systemId" -o tsv)
# Example result: /regions/unitedstates/providers/Microsoft.PowerPlatform/enterprisePolicies/09c8ad9a-...
```

### Step 3 — POST link

```powershell
$envId = "Default-<tenantId>"   # or a bare GUID for non-default envs
$body  = @{ SystemId = $epSystemId } | ConvertTo-Json -Compress

$response = Invoke-WebRequest `
    -Uri "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/environments/$envId/enterprisePolicies/NetworkInjection/link?api-version=2019-10-01" `
    -Method Post `
    -Headers @{ Authorization = "Bearer $token" } `
    -ContentType "application/json" `
    -Body $body `
    -ErrorAction Stop

# 202 Accepted -> async operation
$opLocation = $response.Headers['operation-location']
```

### Step 4 — Poll async operation (202 → final state)

```powershell
if ($opLocation) {
    do {
        Start-Sleep -Seconds 10
        $poll = Invoke-RestMethod -Uri $opLocation -Headers @{ Authorization = "Bearer $token" } -ErrorAction Stop
        $pollState = $poll.state.id   # BAP lifecycle op uses state.id, not status/operationStatus
        Write-Host "  state: $pollState  type: $($poll.type.id)"
    } while ($pollState -notin @('Succeeded','Failed','Canceled'))
    
    if ($pollState -eq 'Succeeded') {
        Write-Host "Link $($poll.type.id) succeeded (op: $($poll.id))"
        # type.id = "NewNetworkInjection" on first link, "SwapNetworkInjection" on re-runs
    } else {
        throw "Link operation failed: $($poll | ConvertTo-Json -Compress)"
    }
}
```

### Step 5 — Verify link state

**Do NOT use the GET endpoint** — `GET .../enterprisePolicies/NetworkInjection?api-version=2019-10-01`
returns 404 regardless of link state. Use the lifecycle op result:

- `type.id = "NewNetworkInjection"` + `state.id = "Succeeded"` → first successful link
- `type.id = "SwapNetworkInjection"` + `state.id = "Succeeded"` → idempotent re-link (link already existed)

**Confirm via allowed ops:**

```powershell
$env = Invoke-RestMethod `
    -Uri "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/environments/$envId/lifecycleOperationsEnforcement?api-version=2019-10-01" `
    -Headers @{ Authorization = "Bearer $token" }
$env.allowedOperations.type.id   # Should include SwapNetworkInjection, RevertNetworkInjection
$env.disallowedOperations.type.id   # NewNetworkInjection should NOT appear here
```

**ARM healthStatus** (`az resource show ... --query "properties.healthStatus"`) may remain
`Undetermined` for an extended period after a successful link. Transition to `Running`
requires PP control plane to establish VNet infrastructure and may only occur when ME
workloads actively use VNet injection. `Undetermined` is NOT a failure when the lifecycle
op shows `Succeeded`.

---

## Constraints and Gotchas

| Constraint | Detail |
|---|---|
| **Governance tier prerequisite** | Default environments have `protectionLevel: "Basic"`. This blocks `NewNetworkInjection` with `400 GovernanceConfig`. Upgrade to `Standard` via `Set-AdminPowerAppEnvironmentGovernanceConfiguration` (see Step 0) before the link call. Direct PATCH to `scopes/admin/environments` silently does nothing. |
| **Environment type** | Trial environments return `400 InvalidLifecycleOperationRequest: NewNetworkInjection cannot be performed on environment of type Trial.` Only Default, Production, Sandbox, Developer types work. |
| **ManageProtectionKeys** | Account must have **Power Platform Administrator** Entra role (tenant-wide) OR **System Administrator** Dataverse role (env-scope). `403 EnvironmentAccess / UserMissingRequiredPermission` means this is missing. |
| **SystemId ≠ ARM ID** | The link body field is `SystemId`, not the ARM resource ID. Always resolve from `az resource show --query "properties.systemId"`. Example: `/regions/unitedstates/providers/Microsoft.PowerPlatform/enterprisePolicies/<guid>` |
| **api-version** | Use `2019-10-01` for the link call. Newer versions may not be routed correctly for this specific path. |
| **Content-Type** | Use `-ContentType "application/json"` with `Invoke-WebRequest`. Setting it in `-Headers` only can produce `415 UnsupportedMediaType`. |
| **Lifecycle op state field** | Poll result uses `state.id` (not `status` or `operationStatus`). Valid terminal values: `Succeeded`, `Failed`, `Canceled`. |
| **Idempotency — re-link = swap** | If the same EP is already linked, re-submitting the link POST returns 202 and completes as `SwapNetworkInjection: Succeeded` (NOT a 400 error). This makes the call fully idempotent. |
| **GET endpoint returns 404** | `GET .../enterprisePolicies/NetworkInjection?api-version=2019-10-01` always returns 404. Use the lifecycle op result (`type.id` + `state.id`) to confirm link state. |
| **healthStatus timing** | ARM `healthStatus` may remain `Undetermined` indefinitely after a successful link. It is NOT a reliable success indicator. Use the lifecycle op state. |
| **App Insights binding — no REST path** | `applicationInsightsId` and related fields do NOT exist in `EnvironmentProperties` on any BAP API version (2016-11-01 → 2024-05-01). All PATCH attempts return `400 InvalidRequestContent`. No public REST or PowerShell cmdlet exists. Configure via PPAC: **Manage (left nav) → Data export → App Insights tab → New data export** (resource picker — no connection string paste needed). Reference: [learn.microsoft.com/power-platform/admin/set-up-export-application-insights](https://learn.microsoft.com/en-us/power-platform/admin/set-up-export-application-insights). |

---

## Related BAP API Calls

```powershell
# List lifecycle ops enforcement (allowed/disallowed operations)
Invoke-RestMethod `
    -Uri "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/environments/$envId/lifecycleOperationsEnforcement?api-version=2019-10-01" `
    -Headers @{ Authorization = "Bearer $token" }

# Get lifecycle op status (use operation-location from the link 202 response)
Invoke-RestMethod `
    -Uri "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/lifecycleOperations/<opId>?api-version=2019-10-01" `
    -Headers @{ Authorization = "Bearer $token" }

# List all environments (non-admin, sees envs you have access to)
Invoke-RestMethod `
    -Uri "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/environments?api-version=2016-11-01" `
    -Headers @{ Authorization = "Bearer $token" }

# Get environment details
Invoke-RestMethod `
    -Uri "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/environments/$envId?api-version=2016-11-01" `
    -Headers @{ Authorization = "Bearer $token" }
```

**Note:** `GET .../enterprisePolicies/NetworkInjection` returns 404 regardless of link state. Do not use it as a pre-check.

---

## Source

Endpoint and body format confirmed from EP module v0.17.0 source:

- `Private/EnvironmentOperations.ps1` — `Set-EnvironmentEnterprisePolicy` function
- `Private/RESTHelpers.ps1` — `Get-PPEndpointUrl` (prod = `https://api.bap.microsoft.com/`)
- `Private/RESTHelpers.ps1` — `Get-PPResourceUrl` (prod token resource = `https://service.powerapps.com/`)
