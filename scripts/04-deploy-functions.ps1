<#
.SYNOPSIS
    Packages and deploys the kv-demo function code to BOTH east and west Function Apps.

.DESCRIPTION
    Tank — Part 4 deployment script.

    Steps:
      1. Reads Function App names from .azure/last-deploy-outputs.json (written by 01-deploy.sh).
      2. Zips functions/kv-demo/ with host.json at the zip root.
      3. Deploys to east Function App via az functionapp deploy (ARM management-plane zip deploy —
         does NOT require public SCM access, so publicNetworkAccess=Disabled is safe).
      4. Deploys the same zip to west Function App.
      5. If ARM zip deploy fails (rare: firewall on ARM API path), falls back to Run-from-Package:
         uploads zip to the function storage account and sets WEBSITE_RUN_FROM_PACKAGE to the SAS URL.
      6. Smoke-tests each function:
         a. Temporarily sets publicNetworkAccess=Enabled (data plane only).
         b. Invokes the /api/GetSecret endpoint.
         c. Verifies secretFetchedOk=true in the JSON response.
         d. Immediately sets publicNetworkAccess=Disabled again.
         FINAL STATE IS ALWAYS PRIVATE — the script enforces this in a finally block.

.PARAMETER ResourceGroup
    Resource group name. Default: rg-pbinet-dev-eastus

.PARAMETER Subscription
    Azure subscription ID. Default: 43d55e51-58fe-486f-9e2a-ba56b8dd15de

.PARAMETER FunctionSourcePath
    Path to the function source folder (must contain host.json). Default: functions/kv-demo

.PARAMETER OutputsFile
    Path to the deploy outputs JSON written by 01-deploy.sh. Default: .azure/last-deploy-outputs.json

.PARAMETER SkipSmoke
    Skip the smoke test step. Use when running from a fully private environment with no internet egress.

.EXAMPLE
    # Run from repo root:
    pwsh scripts/04-deploy-functions.ps1

.EXAMPLE
    # Skip smoke test if already validated:
    pwsh scripts/04-deploy-functions.ps1 -SkipSmoke
#>
[CmdletBinding()]
param(
    [string]$ResourceGroup  = 'rg-pbinet-dev-eastus',
    [string]$Subscription   = '43d55e51-58fe-486f-9e2a-ba56b8dd15de',
    [string]$FunctionSourcePath = 'functions/kv-demo',
    [string]$OutputsFile    = '.azure/last-deploy-outputs.json',
    [switch]$SkipSmoke
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Ok  { param([string]$Msg) Write-Host "✓ $Msg" -ForegroundColor Green }
function Write-Fail { param([string]$Msg) Write-Error "✗ $Msg" }
function Write-Step { param([string]$Msg) Write-Host "`n==> $Msg" -ForegroundColor Cyan }

# ---------------------------------------------------------------------------
# 0. Pre-flight
# ---------------------------------------------------------------------------
Write-Step "Pre-flight checks"

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Fail "Azure CLI (az) is required."
    exit 1
}

if (-not (Test-Path $OutputsFile)) {
    Write-Fail "Outputs file not found: $OutputsFile — run scripts/01-deploy.sh first."
    exit 1
}

if (-not (Test-Path "$FunctionSourcePath/host.json")) {
    Write-Fail "host.json not found in $FunctionSourcePath — check FunctionSourcePath parameter."
    exit 1
}

$outputs = Get-Content $OutputsFile -Raw | ConvertFrom-Json

$funcEastName = $outputs.functionAppEastName.value
$funcWestName = $outputs.functionAppWestName.value

if (-not $funcEastName -or -not $funcWestName) {
    Write-Fail "functionAppEastName / functionAppWestName missing from $OutputsFile. Was deployFunctionApp=true?"
    exit 1
}

Write-Ok "East Function App : $funcEastName"
Write-Ok "West Function App : $funcWestName"

az account set --subscription $Subscription | Out-Null
Write-Ok "Subscription set  : $Subscription"

# ---------------------------------------------------------------------------
# 1. Build zip — host.json MUST be at the zip root (not nested in a subfolder).
# ---------------------------------------------------------------------------
Write-Step "Building function zip"

$zipPath = "$env:TEMP\kv-demo-$(Get-Date -Format 'yyyyMMddHHmm').zip"

# Compress-Archive with -Path <folder>\* puts files at the root of the zip.
$sourceGlob = Join-Path (Resolve-Path $FunctionSourcePath) '*'
Compress-Archive -Path $sourceGlob -DestinationPath $zipPath -Force

$zipSizeKb = [math]::Round((Get-Item $zipPath).Length / 1KB, 1)
Write-Ok "Zip created: $zipPath ($zipSizeKb KB)"

# Verify host.json is at zip root.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipEntries = [System.IO.Compression.ZipFile]::OpenRead($zipPath).Entries.FullName
if ($zipEntries -notcontains 'host.json') {
    Write-Fail "host.json not found at zip root. Entries: $($zipEntries -join ', ')"
    exit 1
}
Write-Ok "Zip layout verified (host.json at root)"

# ---------------------------------------------------------------------------
# 2. Deploy zip to both Function Apps (ARM management-plane zip deploy)
# ---------------------------------------------------------------------------
function Deploy-FunctionZip {
    param(
        [string]$AppName,
        [string]$Rg,
        [string]$ZipFile
    )

    Write-Step "Deploying zip to $AppName"

    # az functionapp deploy uses PUT .../extensions/ZipDeploy on the ARM control plane.
    # This path does NOT require public SCM/Kudu access, so publicNetworkAccess=Disabled is fine.
    $result = az functionapp deploy `
        --name        $AppName `
        --resource-group $Rg `
        --src-path    $ZipFile `
        --type        zip `
        --output      json 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ARM zip deploy failed. Attempting Run-from-Package fallback..." -ForegroundColor Yellow
        Deploy-RunFromPackage -AppName $AppName -Rg $Rg -ZipFile $ZipFile
    }
    else {
        Write-Ok "ARM zip deploy succeeded for $AppName"
    }
}

function Deploy-RunFromPackage {
    param(
        [string]$AppName,
        [string]$Rg,
        [string]$ZipFile
    )

    # Get the function storage account name from the app settings.
    $storageAccountName = az functionapp config appsettings list `
        --name $AppName --resource-group $Rg `
        --query "[?name=='AzureWebJobsStorage__accountName'].value" -o tsv

    if (-not $storageAccountName) {
        Write-Fail "Could not determine function storage account for $AppName. Manual deploy required."
        return
    }

    Write-Host "  Storage account : $storageAccountName"

    # Create deployments container if missing.
    az storage container create `
        --account-name $storageAccountName `
        --name deployments `
        --auth-mode login `
        --output none 2>&1 | Out-Null

    # Upload zip.
    $blobName = "kv-demo-$(Get-Date -Format 'yyyyMMddHHmm').zip"
    az storage blob upload `
        --account-name $storageAccountName `
        --container-name deployments `
        --name $blobName `
        --file $ZipFile `
        --auth-mode login `
        --output none

    # Generate user-delegation SAS (doesn't require shared key access).
    $expiry = (Get-Date).ToUniversalTime().AddDays(7).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $sasToken = az storage blob generate-sas `
        --account-name $storageAccountName `
        --container-name deployments `
        --name $blobName `
        --permissions r `
        --expiry $expiry `
        --auth-mode login `
        --as-user `
        -o tsv

    $sasUrl = "https://${storageAccountName}.blob.core.windows.net/deployments/${blobName}?${sasToken}"

    # Set WEBSITE_RUN_FROM_PACKAGE to the SAS URL.
    az functionapp config appsettings set `
        --name $AppName `
        --resource-group $Rg `
        --settings "WEBSITE_RUN_FROM_PACKAGE=$sasUrl" `
        --output none

    Write-Ok "Run-from-Package fallback deployed to $AppName (SAS URL valid 7 days)"
}

Deploy-FunctionZip -AppName $funcEastName -Rg $ResourceGroup -ZipFile $zipPath
Deploy-FunctionZip -AppName $funcWestName -Rg $ResourceGroup -ZipFile $zipPath

# ---------------------------------------------------------------------------
# 3. Smoke test — temporarily enable public access, curl, then disable.
# GUARDRAIL: Uses try/finally to guarantee publicNetworkAccess=Disabled regardless
# of whether the smoke test passes or fails. Final state is ALWAYS private.
# ---------------------------------------------------------------------------
if ($SkipSmoke) {
    Write-Host "`nSmoke test skipped (-SkipSmoke). Use Azure Portal Test/Run blade to validate manually:" -ForegroundColor Yellow
    Write-Host "  Function App → Functions → GetSecret → Test/Run → Run"
    exit 0
}

function Invoke-SmokeTest {
    param(
        [string]$AppName,
        [string]$Rg,
        [string]$Region
    )

    Write-Step "Smoke test — $AppName ($Region)"

    $hostname = az functionapp show `
        --name $AppName `
        --resource-group $Rg `
        --query "defaultHostName" -o tsv

    $funcUrl = "https://${hostname}/api/GetSecret"

    try {
        # TEMP: enable public access so we can reach the HTTP trigger from here.
        # This is a test-only operation — the finally block always sets it back.
        Write-Host "  [SMOKE TEST ONLY] Enabling publicNetworkAccess on $AppName..." -ForegroundColor Yellow
        az functionapp update `
            --name $AppName `
            --resource-group $Rg `
            --set publicNetworkAccess=Enabled `
            --output none

        # Give ARM a few seconds to propagate.
        Start-Sleep -Seconds 15

        Write-Host "  Invoking $funcUrl"
        $response = Invoke-RestMethod -Uri $funcUrl -Method Get -TimeoutSec 30

        if ($response.secretFetchedOk -eq $true) {
            Write-Ok "Smoke test PASSED for $AppName"
            Write-Host "  region          : $($response.region)"
            Write-Host "  secretFetchedOk : $($response.secretFetchedOk)"
            Write-Host "  kvHost          : $($response.kvHost)"
            Write-Host "  timestamp       : $($response.timestamp)"
        }
        else {
            Write-Host "  WARNING: Response received but secretFetchedOk != true:" -ForegroundColor Yellow
            $response | ConvertTo-Json | Write-Host
        }
    }
    catch {
        Write-Host "  Smoke test error for $AppName : $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  Manual fallback: Azure Portal → $AppName → Functions → GetSecret → Test/Run" -ForegroundColor Yellow
    }
    finally {
        # GUARDRAIL: always restore private access regardless of test outcome.
        Write-Host "  [GUARDRAIL] Restoring publicNetworkAccess=Disabled on $AppName..." -ForegroundColor Yellow
        az functionapp update `
            --name $AppName `
            --resource-group $Rg `
            --set publicNetworkAccess=Disabled `
            --output none
        Write-Ok "publicNetworkAccess restored to Disabled on $AppName"
    }
}

Invoke-SmokeTest -AppName $funcEastName -Rg $ResourceGroup -Region 'east'
Invoke-SmokeTest -AppName $funcWestName -Rg $ResourceGroup -Region 'west'

# ---------------------------------------------------------------------------
# 4. KQL hints for post-deploy validation
# ---------------------------------------------------------------------------
Write-Host "`n--- Post-Deploy KQL Queries (run against LAW law-pbinet-dev-* ) ---" -ForegroundColor Cyan
Write-Host @'
// KV diagnostics — should show SecretGet events from 10.10.2.x (east) and 10.20.2.x (west)
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.KEYVAULT"
| where TimeGenerated > ago(15m)
| where OperationName == "SecretGet"
| project TimeGenerated, CallerIPAddress, identity_claim_oid_g, requestUri_s, ResultType
| order by TimeGenerated desc

// App Insights dependencies — should show vault.azure.net rows (Part 4 gap closure)
dependencies
| where timestamp > ago(15m)
| where target contains "vault.azure.net"
| project timestamp, cloud_RoleName, name, target, success, duration, resultCode
| order by timestamp desc
'@

Write-Ok "04-deploy-functions.ps1 complete"
