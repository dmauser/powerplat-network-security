#requires -Version 7.0
<#
.SYNOPSIS
Verifies and documents the connector telemetry pipeline for the Power Platform
VNet-secured lab (Key Vault private endpoint monitoring via Application Insights).

.DESCRIPTION
This script prints verification commands and guidance for the connector
observability story. It is the SECOND half of the monitoring setup —
scripts/02-configure-pp-vnet.ps1 is the canonical place for the actual
environment-level Application Insights binding; this script verifies that
binding and cross-correlates PP telemetry with Azure resource diagnostics.

MANUAL STEPS (not automatable via script today):
-------------------------------------------------
1.  TENANT-LEVEL ANALYTICS — Enable in PPAC:
    Power Platform admin center → Settings → Tenant settings →
    "Tenant-level analytics" → ON
    Reference: https://learn.microsoft.com/en-us/power-platform/admin/tenant-level-analytics

2.  CUSTOM CONNECTOR DIAGNOSTIC SETTINGS — per connector:
    In the connector definition (make.powerapps.com → custom connectors →
    <your KV connector> → Edit → 4. AI and diagnostics):
    Turn "Enable diagnostic settings" ON.
    This forwards connector invocation traces to the environment-bound
    Application Insights resource.
    Reference: https://learn.microsoft.com/en-us/connectors/custom-connectors/ai-telemetry

3.  APP / FLOW APP INSIGHTS CONFIRMATION:
    For canvas apps and Power Automate flows using the Key Vault custom connector:
    - Canvas apps inherit the environment App Insights binding automatically once
      set via scripts/02-configure-pp-vnet.ps1.
    - Power Automate flows emit telemetry to the environment-bound App Insights
      resource; no per-flow configuration is required.
    - If an app was created before the AI binding was set, republish it to pick
      up the new binding.

WHAT THIS SCRIPT AUTOMATES:
----------------------------
- Reads deploy outputs to confirm the App Insights binding values.
- Calls the BAP admin REST API to VERIFY the binding is active (read-only).
- Prints KQL verification queries you can run against the Log Analytics workspace.
  See docs/monitoring.md for the full KQL library and dashboard ideas (Niobe).

.PARAMETER EnvironmentId
Power Platform environment ID to verify.

.PARAMETER DeployOutputsPath
Optional path to the deployment outputs JSON file.
Defaults to ..\.azure\last-deploy-outputs.json relative to this script.

.PARAMETER WorkspaceId
Log Analytics workspace ID (GUID) to run the correlation query against.
If omitted, the workspace ID is printed for manual use.

.NOTES
Monitoring reference doc: docs/monitoring.md
This script is safe to re-run — it only reads state, never writes.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrWhiteSpace()]
    [string]$EnvironmentId,

    [Parameter()]
    [string]$DeployOutputsPath,

    [Parameter()]
    [string]$WorkspaceId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DefaultDeployOutputsPath = Join-Path -Path $PSScriptRoot -ChildPath '..\.azure\last-deploy-outputs.json'

function Get-ResolvedDeployOutputsPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return [System.IO.Path]::GetFullPath($DefaultDeployOutputsPath)
    }
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location) -ChildPath $Path))
}

function Assert-CommandAvailable {
    param([string]$Name)
    if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' is not available in the current session."
    }
}

function Get-DeployOutputs {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Deployment outputs file not found: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

try {
    Assert-CommandAvailable -Name 'az'

    $resolvedPath = Get-ResolvedDeployOutputsPath -Path $DeployOutputsPath
    $deployOutputs = Get-DeployOutputs -Path $resolvedPath

    $appInsightsResourceId    = [string]$deployOutputs.appInsightsResourceId.value
    $appInsightsConnectionStr = [string]$deployOutputs.appInsightsConnectionString.value
    $keyVaultName             = [string]$deployOutputs.keyVaultName.value

    Write-Host ''
    Write-Host '=== Power Platform Connector Telemetry — Verification ===' -ForegroundColor Cyan
    Write-Host ''

    # -----------------------------------------------------------------------
    # 1. Confirm deploy outputs carry App Insights info
    # -----------------------------------------------------------------------

    if ([string]::IsNullOrWhiteSpace($appInsightsResourceId)) {
        Write-Host '[WARN] appInsightsResourceId is empty in deploy outputs.' -ForegroundColor Yellow
        Write-Host '       Re-deploy with deployMonitoring=true and logAnalyticsWorkspaceId set.'
        Write-Host '       See infra/modules/appInsights.bicep and infra/main.bicep.'
        Write-Host ''
    }
    else {
        Write-Host "[OK] App Insights resource ID : $appInsightsResourceId" -ForegroundColor Green
        Write-Host "[OK] Connection string present : $(-not [string]::IsNullOrWhiteSpace($appInsightsConnectionStr))" -ForegroundColor Green
    }

    # -----------------------------------------------------------------------
    # 2. Verify the PP environment AI binding via BAP REST API (read-only)
    # -----------------------------------------------------------------------

    Write-Host ''
    Write-Host '--- Verifying environment App Insights binding (BAP REST, read-only) ---'

    $ppTokenResult = az account get-access-token --resource 'https://service.powerapps.com/' --output json 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($ppTokenResult)) {
        Write-Host '[SKIP] Unable to acquire Power Apps token — skipping live binding check.' -ForegroundColor Yellow
        Write-Host '       Run: az login and retry.'
    }
    else {
        $ppToken = ($ppTokenResult | ConvertFrom-Json).accessToken
        $bapUri = "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments/$([Uri]::EscapeDataString($EnvironmentId))?api-version=2023-06-01"
        $headers = @{ Authorization = "Bearer $ppToken"; 'Content-Type' = 'application/json' }

        $envData = Invoke-RestMethod -Uri $bapUri -Method Get -Headers $headers -ErrorAction Stop
        $boundAiId = [string]$envData.properties.applicationInsightsId

        if ([string]::IsNullOrWhiteSpace($boundAiId)) {
            Write-Host '[WARN] No Application Insights resource is bound to this environment.' -ForegroundColor Yellow
            Write-Host '       Run scripts/02-configure-pp-vnet.ps1 with a deploy that includes AI outputs.'
        }
        elseif ($boundAiId -ieq $appInsightsResourceId) {
            Write-Host "[OK] Environment AI binding matches deploy output: $boundAiId" -ForegroundColor Green
        }
        else {
            Write-Host "[WARN] Environment AI binding does NOT match deploy output." -ForegroundColor Yellow
            Write-Host "       Bound  : $boundAiId"
            Write-Host "       Expected: $appInsightsResourceId"
            Write-Host '       Re-run scripts/02-configure-pp-vnet.ps1 to reconcile.'
        }
    }

    # -----------------------------------------------------------------------
    # 3. KQL verification queries
    #
    # Run these in the Log Analytics workspace linked to the App Insights
    # resource. See docs/monitoring.md for the full KQL library and alert
    # rules (Niobe owns that doc).
    # -----------------------------------------------------------------------

    Write-Host ''
    Write-Host '--- KQL verification queries (run in Log Analytics workspace) ---' -ForegroundColor Cyan
    Write-Host 'Workspace ID from outputs or Trinity LAW module output logAnalyticsWorkspaceId.'
    Write-Host ''

    $kvNameHint = if ([string]::IsNullOrWhiteSpace($keyVaultName)) { '<keyVaultName>' } else { $keyVaultName }

    $kqlPpRequests = @"
// PP requests to Key Vault via private endpoint — last 1 hour
// Source: docs/monitoring.md (Niobe)
requests
| where timestamp > ago(1h)
| where url contains "vault.azure.net"
| project timestamp, name, resultCode, duration, cloud_RoleName
| order by timestamp desc
| take 50
"@

    $kqlCrossCorrelation = @"
// Cross-correlate PP requests with KV AuditEvent (same workspace)
// Confirms traffic uses the private endpoint (callerIpAddress = 10.x.x.x)
// Source: docs/monitoring.md (Niobe)
let ppOps = requests
    | where timestamp > ago(1h)
    | where url contains "vault.azure.net"
    | project ppTime = timestamp, ppDuration = duration, ppResult = resultCode, operation_Id;
AzureDiagnostics
| where ResourceType == "VAULTS" and Category == "AuditEvent"
| where TimeGenerated > ago(1h)
| where ResourceId contains "$kvNameHint"
| project kvTime = TimeGenerated, operationName, callerIpAddress, ResultType, CorrelationId
| join kind=leftouter (ppOps) on `$left.CorrelationId == `$right.operation_Id
| project kvTime, operationName, callerIpAddress, ResultType, ppResult, ppDuration
| order by kvTime desc
| take 50
"@

    $kqlPeVerify = @"
// Verify Key Vault traffic is going through the private endpoint (not public)
// callerIpAddress should be a 10.x.x.x address from snet-pp-delegated
// Source: docs/monitoring.md (Niobe)
AzureDiagnostics
| where ResourceType == "VAULTS" and Category == "AuditEvent"
| where TimeGenerated > ago(1h)
| where ResourceId contains "$kvNameHint"
| summarize requestCount = count() by callerIpAddress, ResultType
| order by requestCount desc
"@

    Write-Host 'Query 1 — PP requests to Key Vault:' -ForegroundColor Yellow
    Write-Host $kqlPpRequests
    Write-Host ''
    Write-Host 'Query 2 — Cross-correlate PP requests + KV AuditEvent:' -ForegroundColor Yellow
    Write-Host $kqlCrossCorrelation
    Write-Host ''
    Write-Host 'Query 3 — Confirm PE path (callerIpAddress should be 10.x.x.x):' -ForegroundColor Yellow
    Write-Host $kqlPeVerify
    Write-Host ''

    # -----------------------------------------------------------------------
    # 4. Optional: run query via az monitor log-analytics query
    # -----------------------------------------------------------------------

    if (-not [string]::IsNullOrWhiteSpace($WorkspaceId)) {
        Write-Host "--- Running live PE verification query against workspace $WorkspaceId ---"
        $query = "AzureDiagnostics | where ResourceType == 'VAULTS' and Category == 'AuditEvent' | where TimeGenerated > ago(1h) | summarize count() by callerIpAddress, ResultType"
        az monitor log-analytics query --workspace $WorkspaceId --analytics-query $query --output table
    }
    else {
        Write-Host '[INFO] Pass -WorkspaceId <guid> to run the live PE verification query.' -ForegroundColor DarkGray
        Write-Host '       Workspace ID is in Trinity LAW deploy output logAnalyticsWorkspaceId.'
    }

    Write-Host ''
    Write-Host 'Manual steps still required (not automatable):' -ForegroundColor Yellow
    Write-Host '  1. Enable Tenant-level analytics in PPAC.'
    Write-Host '     https://learn.microsoft.com/en-us/power-platform/admin/tenant-level-analytics'
    Write-Host '  2. Turn on "Enable diagnostic settings" for each custom connector in make.powerapps.com.'
    Write-Host '     https://learn.microsoft.com/en-us/connectors/custom-connectors/ai-telemetry'
    Write-Host '  3. Republish canvas apps created before the AI binding was set.'
    Write-Host ''
    Write-Host 'See docs/monitoring.md for full KQL library, alert rules, and dashboard setup.' -ForegroundColor Cyan
}
catch {
    Write-Error -Message $_.Exception.Message
    Write-Host ''
    Write-Host 'Fix-up steps:' -ForegroundColor Yellow
    Write-Host '  1. Confirm az login is complete.'
    Write-Host '  2. Confirm scripts/01-deploy.sh produced the deploy outputs file.'
    Write-Host '  3. Confirm scripts/02-configure-pp-vnet.ps1 completed with deployMonitoring=true.'
    exit 1
}
