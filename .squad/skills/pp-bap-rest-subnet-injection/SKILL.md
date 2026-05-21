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
        Write-Host "  status: $($poll.status ?? $poll.operationStatus)"
    } while ($poll.status -notin @('Succeeded','Failed','Canceled') -and $poll.operationStatus -notin @('Succeeded','Failed'))
    
    if ($poll.status -eq 'Succeeded' -or $poll.operationStatus -eq 'Succeeded') {
        Write-Host "Link succeeded"
    } else {
        throw "Link operation failed: $($poll | ConvertTo-Json -Compress)"
    }
}
```

### Step 5 — Verify EP healthStatus transitions

```bash
az resource show \
  --ids <epArmId> \
  --api-version 2020-10-30-preview \
  --query "{healthStatus: properties.healthStatus}" \
  -o json
# Expected after successful link: "healthStatus": "Running"
```

---

## Constraints and Gotchas

| Constraint | Detail |
|---|---|
| **Environment type** | Trial environments return `400 InvalidLifecycleOperationRequest: NewNetworkInjection cannot be performed on environment of type Trial.` Only Default, Production, Sandbox, Developer types work. |
| **ManageProtectionKeys** | Account must have **Power Platform Administrator** Entra role (tenant-wide) OR **System Administrator** Dataverse role (env-scope). `403 EnvironmentAccess / UserMissingRequiredPermission` means this is missing. |
| **SystemId ≠ ARM ID** | The link body field is `SystemId`, not the ARM resource ID. Always resolve from `az resource show --query "properties.systemId"`. Example: `/regions/unitedstates/providers/Microsoft.PowerPlatform/enterprisePolicies/<guid>` |
| **api-version** | Use `2019-10-01` for the link call. Newer versions may not be routed correctly for this specific path. |
| **Content-Type** | Use `-ContentType "application/json"` with `Invoke-WebRequest`. Setting it in `-Headers` only can produce `415 UnsupportedMediaType`. |
| **healthStatus timing** | The ARM resource `healthStatus` transitions from `Undetermined` → `Running` only after a successful link AND after PP control plane has processed the association. May take 1-5 minutes. |
| **Idempotency** | If the same EP is already linked, the POST returns `400 InvalidLifecycleOperationRequest` with `SwapNetworkInjection` in the message (policy already linked). Check `GET /environments/{id}/enterprisePolicies/NetworkInjection` first. |

---

## Related BAP API Calls

```powershell
# Check current linked EP on an environment
Invoke-RestMethod `
    -Uri "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/environments/$envId/enterprisePolicies/NetworkInjection?api-version=2019-10-01" `
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

---

## Source

Endpoint and body format confirmed from EP module v0.17.0 source:

- `Private/EnvironmentOperations.ps1` — `Set-EnvironmentEnterprisePolicy` function
- `Private/RESTHelpers.ps1` — `Get-PPEndpointUrl` (prod = `https://api.bap.microsoft.com/`)
- `Private/RESTHelpers.ps1` — `Get-PPResourceUrl` (prod token resource = `https://service.powerapps.com/`)
