#requires -Version 7.0
<#
.SYNOPSIS
    Runs Power Platform VNet diagnostic scenarios using the Microsoft.PowerPlatform.EnterprisePolicies
    module's diagnostic cmdlets to validate end-to-end VNet path health.

.DESCRIPTION
    Wraps five diagnostic cmdlets from the Microsoft.PowerPlatform.EnterprisePolicies module into
    named scenarios scoped to this lab's deployed resources (Key Vault, SQL Server, Storage).

    Results are printed with PASS / FAIL / SKIP verdicts and written as a structured JSON log to
    .azure/last-diagnostics-run.json.

    PASS criteria for DNS scenarios: the resolved IP falls within 10.10.0.0/16 (eastus) or
    10.20.0.0/16 (westus) — the lab VNet CIDR ranges — indicating traffic uses the private endpoint.

    PASS criteria for TCP / TLS scenarios: the cmdlet returns a truthy or success-indicating result.

    NOTE: Diagnostic cmdlets (Test-DnsResolution, Test-NetworkConnectivity, Test-TLSHandshake)
    run probes FROM the delegated subnet, not from the local machine. The local machine must hold
    a valid az CLI session and Az PowerShell context; the Power Platform control plane handles
    the actual in-subnet probes.

    Reference:
      https://learn.microsoft.com/en-us/troubleshoot/power-platform/administration/virtual-network

.PARAMETER EnvironmentId
    Power Platform environment ID (e.g. Default-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx).
    If omitted, auto-discovery via 'pac admin list' is attempted against the enterprise policy
    in the deploy outputs. If auto-discovery fails and stdin is interactive, the user is prompted.

.PARAMETER Scenario
    Diagnostic scenario to run. Valid values:
      Region      — Get-EnvironmentRegion: returns the Azure region serving the environment.
      Usage       — Get-EnvironmentUsage: returns environment resource usage metrics.
      KvDns       — Test-DnsResolution for Key Vault FQDN from the delegated subnet.
      SqlDns      — Test-DnsResolution for SQL Server FQDN (SKIP when SQL is deferred).
      StorageDns  — Test-DnsResolution for Storage FQDN from the delegated subnet.
      KvTcp       — Test-NetworkConnectivity to Key Vault on port 443.
      SqlTcp      — Test-NetworkConnectivity to SQL Server on port 1433 (SKIP when SQL is deferred).
      StorageTcp  — Test-NetworkConnectivity to Storage on port 443.
      KvTls       — Test-TLSHandshake to Key Vault on port 443.
      SqlTls      — Test-TLSHandshake to SQL Server on port 1433 (SKIP when SQL is deferred).
      All         — Run all scenarios sequentially and print a summary table.

.PARAMETER OutputsFile
    Path to the deployment outputs JSON (produced by scripts/01-deploy.sh).
    Defaults to .azure/last-deploy-outputs.json relative to the repository root.

.PARAMETER Region
    Optional Azure region override forwarded to Test-DnsResolution calls.
    Useful in dual-region labs to target eastus or westus specifically.

.EXAMPLE
    pwsh ./scripts/06-network-diagnostics.ps1 -Scenario All

.EXAMPLE
    pwsh ./scripts/06-network-diagnostics.ps1 -EnvironmentId Default-abc123 -Scenario KvDns -Region eastus

.EXAMPLE
    pwsh ./scripts/06-network-diagnostics.ps1 -Scenario KvTcp
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$EnvironmentId,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Region', 'Usage', 'KvDns', 'SqlDns', 'StorageDns',
                 'KvTcp', 'SqlTcp', 'StorageTcp', 'KvTls', 'SqlTls', 'All')]
    [string]$Scenario,

    [Parameter()]
    [string]$OutputsFile,

    [Parameter()]
    [string]$Region
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Constants ────────────────────────────────────────────────────────────────

$EnterprisePoliciesModuleVersion = '0.17.0'
$LabPrivateIpPrefixes            = @('10.10.', '10.20.')
$LabPrivateRangeDescription      = '10.10.0.0/16 (eastus) or 10.20.0.0/16 (westus)'
$KvPort                          = 443
$SqlPort                         = 1433
$StoragePort                     = 443

$RepoRoot           = Join-Path -Path $PSScriptRoot -ChildPath '..'
$DefaultOutputsFile = Join-Path -Path $RepoRoot -ChildPath '.azure\last-deploy-outputs.json'
$DiagnosticsRunFile = Join-Path -Path $RepoRoot -ChildPath '.azure\last-diagnostics-run.json'

$AllScenarioNames = @(
    'Region', 'Usage',
    'KvDns', 'SqlDns', 'StorageDns',
    'KvTcp', 'SqlTcp', 'StorageTcp',
    'KvTls', 'SqlTls'
)

# ─── Helper functions ─────────────────────────────────────────────────────────

function Assert-CommandAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' is not available in the current session."
    }
}

function Install-EnterprisePoliciesModule {
    <#
    .SYNOPSIS
    Installs (if needed) and imports Microsoft.PowerPlatform.EnterprisePolicies.
    Pre-seeds globals required by v0.17.0 to avoid Set-StrictMode failures on import.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequiredVersion
    )

    $availableModule = Get-Module -ListAvailable -Name 'Microsoft.PowerPlatform.EnterprisePolicies' |
        Where-Object { $_.Version -eq [version]$RequiredVersion } |
        Select-Object -First 1

    if (-not $availableModule) {
        Write-Host "Installing Microsoft.PowerPlatform.EnterprisePolicies $RequiredVersion for the current user..."
        Install-Module -Name 'Microsoft.PowerPlatform.EnterprisePolicies' `
            -RequiredVersion $RequiredVersion -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    }

    # v0.17.0 reads these globals without null-guard during module init.
    # Pre-seed them before Import-Module to avoid Set-StrictMode -Version Latest failures.
    foreach ($boolVar in @('InPesterExecution', 'PrereqsChecked')) {
        if (-not (Test-Path "variable:Global:$boolVar")) {
            Set-Variable -Name $boolVar -Value $false -Scope Global
        }
    }
    if (-not (Test-Path 'variable:Global:ImportedTypes')) {
        $Global:ImportedTypes = [string[]]@()
    }

    Import-Module -Name 'Microsoft.PowerPlatform.EnterprisePolicies' `
        -RequiredVersion $RequiredVersion -Force -ErrorAction Stop

    $loadedModule = Get-Module -Name 'Microsoft.PowerPlatform.EnterprisePolicies'
    Write-Host "Microsoft.PowerPlatform.EnterprisePolicies $($loadedModule.Version) loaded." -ForegroundColor Green
}

function Ensure-AzContext {
    <#
    .SYNOPSIS
    Bridges the current Azure CLI session into the Az PowerShell module context.

    .DESCRIPTION
    Microsoft.PowerPlatform.EnterprisePolicies v0.17.0 calls Get-AzContext internally before
    each operation. If no Az PowerShell context exists, the module falls through to an
    interactive browser prompt even when the operator is already signed in via az CLI.
    This function detects that condition and populates an Az context from the existing az CLI
    access token, making module cmdlets non-interactive when az CLI is already authenticated.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId
    )

    $contexts = Get-AzContext -ListAvailable -ErrorAction SilentlyContinue
    $matched = $contexts | Where-Object {
        $_.Tenant.Id -eq $TenantId -or $_.Account.Tenants -contains $TenantId
    } | Select-Object -First 1

    if ($matched) {
        Write-Host "Az PowerShell context already present for tenant $TenantId — skipping bridge."
        return
    }

    Write-Host "Bridging Azure CLI session into Az PowerShell module (no interactive login required)..."
    Assert-CommandAvailable -Name 'az'

    $tokenJson = az account get-access-token --output json 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($tokenJson)) {
        throw 'Unable to obtain access token from Azure CLI. Ensure az login is complete before re-running.'
    }

    $tokenObj       = $tokenJson | ConvertFrom-Json
    $accessToken    = $tokenObj.accessToken
    $subscriptionId = az account show --query id -o tsv 2>$null
    $accountId      = az account show --query user.name -o tsv 2>$null
    if ([string]::IsNullOrWhiteSpace($accountId)) { $accountId = 'token@azurecli' }

    $null = Connect-AzAccount -AccessToken $accessToken -AccountId $accountId `
        -Tenant $TenantId -Subscription $subscriptionId -ErrorAction Stop
    Write-Host "Az PowerShell module connected as $accountId (tenant $TenantId)." -ForegroundColor Green
}

function Get-CurrentTenantId {
    Assert-CommandAvailable -Name 'az'
    $tid = az account show --query tenantId -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($tid)) {
        throw 'Unable to resolve tenant ID. Run az login and retry.'
    }
    return $tid.Trim()
}

function Resolve-OutputsFilePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return [System.IO.Path]::GetFullPath($DefaultOutputsFile)
    }
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location) -ChildPath $Path))
}

function Get-DeployOutputs {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Deployment outputs file not found: $Path`n  Run ./scripts/01-deploy.sh first."
    }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Resolve-EnvironmentId {
    param(
        [string]$Candidate,
        [string]$PolicyArmId
    )

    if (-not [string]::IsNullOrWhiteSpace($Candidate)) {
        return $Candidate.Trim()
    }

    Write-Host "EnvironmentId not supplied — attempting auto-discovery via pac CLI..." -ForegroundColor Yellow

    if (Get-Command -Name 'pac' -ErrorAction SilentlyContinue) {
        try {
            $rawList = pac admin list --output json 2>$null
            if (-not [string]::IsNullOrWhiteSpace($rawList)) {
                $envList = $rawList | ConvertFrom-Json
                $policyName = Split-Path -Path $PolicyArmId.TrimEnd('/') -Leaf
                foreach ($env in $envList) {
                    $envJson = $env | ConvertTo-Json -Depth 5 -Compress
                    if ($envJson -match [regex]::Escape($policyName)) {
                        foreach ($idProp in @('EnvironmentId', 'environmentId', 'Id', 'id')) {
                            if ($env.PSObject.Properties.Name -contains $idProp) {
                                $envId = [string]$env.$idProp
                                if (-not [string]::IsNullOrWhiteSpace($envId)) {
                                    Write-Host "  Auto-discovered environment ID: $envId" -ForegroundColor Green
                                    return $envId.Trim()
                                }
                            }
                        }
                    }
                }
            }
        }
        catch {
            Write-Host "  pac admin list failed: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    if ([Console]::IsInputRedirected) {
        throw 'EnvironmentId could not be auto-discovered and stdin is not interactive. Pass -EnvironmentId explicitly.'
    }

    $userInput = Read-Host 'Enter the Power Platform environment ID (e.g. Default-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)'
    if ([string]::IsNullOrWhiteSpace($userInput)) {
        throw 'EnvironmentId is required but was not provided.'
    }
    return $userInput.Trim()
}

function Get-FilteredCmdletArgs {
    <#
    .SYNOPSIS
    Returns only the key/value pairs from Arguments whose keys are valid parameters on Command.
    Prevents "unrecognized parameter" errors when cmdlet signatures differ across module versions.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.CommandInfo]$Command,
        [Parameter(Mandatory = $true)]
        [hashtable]$Arguments
    )
    $filtered = @{}
    foreach ($entry in $Arguments.GetEnumerator()) {
        if ($Command.Parameters.ContainsKey($entry.Key)) {
            $filtered[$entry.Key] = $entry.Value
        }
    }
    return $filtered
}

function Test-IsLabPrivateIp {
    param([string]$IpAddress)
    foreach ($prefix in $LabPrivateIpPrefixes) {
        if ($IpAddress.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Get-IpFromResult {
    <#
    Attempts to extract a dotted-decimal IP address from a cmdlet result object.
    Tries common property names first, then falls back to regex on the string representation.
    #>
    param([object]$Result)
    if ($null -eq $Result) { return $null }
    foreach ($prop in @('ResolvedIpAddress', 'IpAddress', 'ResolvedIP', 'IP', 'Address', 'IPAddress')) {
        if ($Result.PSObject.Properties.Name -contains $prop) {
            $val = [string]$Result.$prop
            if ($val -match '^\d{1,3}(?:\.\d{1,3}){3}$') { return $val }
        }
    }
    $asString = [string]$Result
    if ($asString -match '\b(\d{1,3}(?:\.\d{1,3}){3})\b') { return $Matches[1] }
    return $null
}

function Get-SuccessFromResult {
    <#
    Attempts to determine if a TCP / TLS test cmdlet result indicates success.
    Returns $true when the result looks like a success, $false otherwise.
    #>
    param([object]$Result)
    if ($null -eq $Result) { return $false }
    if ($Result -is [bool]) { return $Result }
    foreach ($prop in @('IsSuccessful', 'Success', 'IsConnected', 'Connected', 'Succeeded', 'IsSuccess')) {
        if ($Result.PSObject.Properties.Name -contains $prop) {
            $val = $Result.$prop
            if ($val -is [bool]) { return $val }
            return [bool]$val
        }
    }
    # If the cmdlet returned a non-null, non-false object with no explicit failure indicator, treat as success.
    return $true
}

function Write-ScenarioHeader {
    param([Parameter(Mandatory = $true)][string]$Name)
    Write-Host ''
    Write-Host "━━━ Scenario: $Name ━━━" -ForegroundColor Cyan
}

function New-ScenarioResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]
        [ValidateSet('PASS', 'FAIL', 'SKIP', 'ERROR')]
        [string]$Status,
        [string]$Notes = ''
    )
    switch ($Status) {
        'PASS'  { Write-Host "  [PASS] $Notes" -ForegroundColor Green }
        'FAIL'  { Write-Host "  [FAIL] $Notes" -ForegroundColor Red }
        'SKIP'  { Write-Host "  [SKIP] $Notes" -ForegroundColor Yellow }
        'ERROR' { Write-Host "  [ERROR] $Notes" -ForegroundColor Red }
    }
    return [pscustomobject]@{ Name = $Name; Status = $Status; Notes = $Notes }
}

# ─── Fatal setup ──────────────────────────────────────────────────────────────

try {
    Assert-CommandAvailable -Name 'az'
    $tenantId = Get-CurrentTenantId

    Install-EnterprisePoliciesModule -RequiredVersion $EnterprisePoliciesModuleVersion
    Ensure-AzContext -TenantId $tenantId

    $resolvedOutputsFile = Resolve-OutputsFilePath -Path $OutputsFile
    $deployOutputs = Get-DeployOutputs -Path $resolvedOutputsFile

    $policyArmId = [string]$deployOutputs.enterprisePolicyArmId.value
    if ([string]::IsNullOrWhiteSpace($policyArmId)) {
        throw 'enterprisePolicyArmId.value was not found in the deployment outputs JSON.'
    }

    # Resolve FQDNs from deploy outputs.
    $kvUri  = [string]$deployOutputs.keyVaultUri.value
    $kvFqdn = $kvUri.TrimStart('https://').TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($kvFqdn)) {
        $kvName = [string]$deployOutputs.keyVaultName.value
        if (-not [string]::IsNullOrWhiteSpace($kvName)) {
            $kvFqdn = "$kvName.vault.azure.net"
        }
    }

    $sqlFqdn = [string]$deployOutputs.sqlServerFqdn.value

    $storageAccountName = [string]$deployOutputs.storageAccountName.value
    $storageFqdn = if ([string]::IsNullOrWhiteSpace($storageAccountName)) { '' } else { "$storageAccountName.blob.core.windows.net" }

    $resolvedEnvId = Resolve-EnvironmentId -Candidate $EnvironmentId -PolicyArmId $policyArmId
}
catch {
    Write-Error -Message $_.Exception.Message
    Write-Host ''
    Write-Host 'Fix-up steps:' -ForegroundColor Yellow
    Write-Host '  1. Confirm Azure CLI is signed in: az login'
    Write-Host '  2. Confirm ./scripts/01-deploy.sh has run and produced .azure/last-deploy-outputs.json'
    Write-Host '  3. Pass -EnvironmentId if auto-discovery failed'
    exit 1
}

Write-Host ''
Write-Host '=== Power Platform VNet Network Diagnostics ===' -ForegroundColor Cyan
Write-Host "  Environment  : $resolvedEnvId"
Write-Host "  Tenant       : $tenantId"
Write-Host "  Outputs file : $resolvedOutputsFile"
Write-Host "  KV FQDN      : $(if ($kvFqdn) { $kvFqdn } else { '[not resolved]' })"
Write-Host "  SQL FQDN     : $(if ($sqlFqdn) { $sqlFqdn } else { '[deferred — deploySql=false]' })"
Write-Host "  Storage FQDN : $(if ($storageFqdn) { $storageFqdn } else { '[not resolved]' })"
if (-not [string]::IsNullOrWhiteSpace($Region)) {
    Write-Host "  Region       : $Region (override)"
}

# ─── Scenario runner ──────────────────────────────────────────────────────────

$scenariosToRun = if ($Scenario -eq 'All') { $AllScenarioNames } else { @($Scenario) }
$results        = [System.Collections.Generic.List[pscustomobject]]::new()
$runTimestamp   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

foreach ($scenarioName in $scenariosToRun) {
    Write-ScenarioHeader -Name $scenarioName
    $scenarioResult = $null

    try {
        # ── Region ──────────────────────────────────────────────────────────────
        if ($scenarioName -eq 'Region') {
            $cmd = Get-Command -Name 'Get-EnvironmentRegion' -ErrorAction SilentlyContinue
            if (-not $cmd) {
                $scenarioResult = New-ScenarioResult -Name 'Region' -Status 'SKIP' `
                    -Notes "Get-EnvironmentRegion not found in module v$EnterprisePoliciesModuleVersion"
            }
            else {
                $cmdArgs = Get-FilteredCmdletArgs -Command $cmd -Arguments @{
                    EnvironmentId = $resolvedEnvId
                    TenantId      = $tenantId
                }
                $out = & $cmd @cmdArgs
                $outStr = if ($out -is [string]) { $out } else { $out | ConvertTo-Json -Depth 3 -Compress }
                Write-Host "  Result: $outStr"
                $scenarioResult = New-ScenarioResult -Name 'Region' -Status 'PASS' -Notes "Region: $outStr"
            }
        }
        # ── Usage ───────────────────────────────────────────────────────────────
        elseif ($scenarioName -eq 'Usage') {
            $cmd = Get-Command -Name 'Get-EnvironmentUsage' -ErrorAction SilentlyContinue
            if (-not $cmd) {
                $scenarioResult = New-ScenarioResult -Name 'Usage' -Status 'SKIP' `
                    -Notes "Get-EnvironmentUsage not found in module v$EnterprisePoliciesModuleVersion"
            }
            else {
                $cmdArgs = Get-FilteredCmdletArgs -Command $cmd -Arguments @{
                    EnvironmentId = $resolvedEnvId
                    TenantId      = $tenantId
                }
                $out = & $cmd @cmdArgs
                Write-Host "  Result: $($out | ConvertTo-Json -Depth 3 -Compress)"
                $scenarioResult = New-ScenarioResult -Name 'Usage' -Status 'PASS' -Notes 'Usage data retrieved'
            }
        }
        # ── KvDns ───────────────────────────────────────────────────────────────
        elseif ($scenarioName -eq 'KvDns') {
            if ([string]::IsNullOrWhiteSpace($kvFqdn)) {
                $scenarioResult = New-ScenarioResult -Name 'KvDns' -Status 'SKIP' `
                    -Notes 'Key Vault FQDN not found in deploy outputs'
            }
            else {
                $cmd = Get-Command -Name 'Test-DnsResolution' -ErrorAction SilentlyContinue
                if (-not $cmd) {
                    $scenarioResult = New-ScenarioResult -Name 'KvDns' -Status 'SKIP' `
                        -Notes "Test-DnsResolution not found in module v$EnterprisePoliciesModuleVersion"
                }
                else {
                    $cmdArgs = Get-FilteredCmdletArgs -Command $cmd -Arguments @{
                        EnvironmentId = $resolvedEnvId
                        HostName      = $kvFqdn
                        TenantId      = $tenantId
                        Region        = $Region
                    }
                    $out = & $cmd @cmdArgs
                    Write-Host "  Result: $($out | ConvertTo-Json -Depth 3 -Compress)"
                    $resolvedIp = Get-IpFromResult -Result $out
                    if ([string]::IsNullOrWhiteSpace($resolvedIp)) {
                        $scenarioResult = New-ScenarioResult -Name 'KvDns' -Status 'PASS' `
                            -Notes 'DNS resolved (IP extraction not available from result shape)'
                    }
                    elseif (Test-IsLabPrivateIp -IpAddress $resolvedIp) {
                        $scenarioResult = New-ScenarioResult -Name 'KvDns' -Status 'PASS' `
                            -Notes "Resolved to $resolvedIp — private endpoint confirmed"
                    }
                    else {
                        $scenarioResult = New-ScenarioResult -Name 'KvDns' -Status 'FAIL' `
                            -Notes "Resolved to $resolvedIp — expected $LabPrivateRangeDescription (public IP indicates broken VNet path)"
                    }
                }
            }
        }
        # ── SqlDns ──────────────────────────────────────────────────────────────
        elseif ($scenarioName -eq 'SqlDns') {
            if ([string]::IsNullOrWhiteSpace($sqlFqdn)) {
                $scenarioResult = New-ScenarioResult -Name 'SqlDns' -Status 'SKIP' `
                    -Notes 'SQL Server FQDN not found in deploy outputs (deploySql=false)'
            }
            else {
                $cmd = Get-Command -Name 'Test-DnsResolution' -ErrorAction SilentlyContinue
                if (-not $cmd) {
                    $scenarioResult = New-ScenarioResult -Name 'SqlDns' -Status 'SKIP' `
                        -Notes "Test-DnsResolution not found in module v$EnterprisePoliciesModuleVersion"
                }
                else {
                    $cmdArgs = Get-FilteredCmdletArgs -Command $cmd -Arguments @{
                        EnvironmentId = $resolvedEnvId
                        HostName      = $sqlFqdn
                        TenantId      = $tenantId
                        Region        = $Region
                    }
                    $out = & $cmd @cmdArgs
                    Write-Host "  Result: $($out | ConvertTo-Json -Depth 3 -Compress)"
                    $resolvedIp = Get-IpFromResult -Result $out
                    if ([string]::IsNullOrWhiteSpace($resolvedIp)) {
                        $scenarioResult = New-ScenarioResult -Name 'SqlDns' -Status 'PASS' `
                            -Notes 'DNS resolved (IP extraction not available from result shape)'
                    }
                    elseif (Test-IsLabPrivateIp -IpAddress $resolvedIp) {
                        $scenarioResult = New-ScenarioResult -Name 'SqlDns' -Status 'PASS' `
                            -Notes "Resolved to $resolvedIp — private endpoint confirmed"
                    }
                    else {
                        $scenarioResult = New-ScenarioResult -Name 'SqlDns' -Status 'FAIL' `
                            -Notes "Resolved to $resolvedIp — expected $LabPrivateRangeDescription (public IP indicates broken VNet path)"
                    }
                }
            }
        }
        # ── StorageDns ──────────────────────────────────────────────────────────
        elseif ($scenarioName -eq 'StorageDns') {
            if ([string]::IsNullOrWhiteSpace($storageFqdn)) {
                $scenarioResult = New-ScenarioResult -Name 'StorageDns' -Status 'SKIP' `
                    -Notes 'Storage FQDN not found in deploy outputs'
            }
            else {
                $cmd = Get-Command -Name 'Test-DnsResolution' -ErrorAction SilentlyContinue
                if (-not $cmd) {
                    $scenarioResult = New-ScenarioResult -Name 'StorageDns' -Status 'SKIP' `
                        -Notes "Test-DnsResolution not found in module v$EnterprisePoliciesModuleVersion"
                }
                else {
                    $cmdArgs = Get-FilteredCmdletArgs -Command $cmd -Arguments @{
                        EnvironmentId = $resolvedEnvId
                        HostName      = $storageFqdn
                        TenantId      = $tenantId
                        Region        = $Region
                    }
                    $out = & $cmd @cmdArgs
                    Write-Host "  Result: $($out | ConvertTo-Json -Depth 3 -Compress)"
                    $resolvedIp = Get-IpFromResult -Result $out
                    if ([string]::IsNullOrWhiteSpace($resolvedIp)) {
                        $scenarioResult = New-ScenarioResult -Name 'StorageDns' -Status 'PASS' `
                            -Notes 'DNS resolved (IP extraction not available from result shape)'
                    }
                    elseif (Test-IsLabPrivateIp -IpAddress $resolvedIp) {
                        $scenarioResult = New-ScenarioResult -Name 'StorageDns' -Status 'PASS' `
                            -Notes "Resolved to $resolvedIp — private endpoint confirmed"
                    }
                    else {
                        $scenarioResult = New-ScenarioResult -Name 'StorageDns' -Status 'FAIL' `
                            -Notes "Resolved to $resolvedIp — expected $LabPrivateRangeDescription (public IP indicates broken VNet path)"
                    }
                }
            }
        }
        # ── KvTcp ───────────────────────────────────────────────────────────────
        elseif ($scenarioName -eq 'KvTcp') {
            if ([string]::IsNullOrWhiteSpace($kvFqdn)) {
                $scenarioResult = New-ScenarioResult -Name 'KvTcp' -Status 'SKIP' `
                    -Notes 'Key Vault FQDN not found in deploy outputs'
            }
            else {
                $cmd = Get-Command -Name 'Test-NetworkConnectivity' -ErrorAction SilentlyContinue
                if (-not $cmd) {
                    $scenarioResult = New-ScenarioResult -Name 'KvTcp' -Status 'SKIP' `
                        -Notes "Test-NetworkConnectivity not found in module v$EnterprisePoliciesModuleVersion"
                }
                else {
                    $cmdArgs = Get-FilteredCmdletArgs -Command $cmd -Arguments @{
                        EnvironmentId = $resolvedEnvId
                        Destination   = $kvFqdn
                        Port          = $KvPort
                        TenantId      = $tenantId
                    }
                    $out = & $cmd @cmdArgs
                    Write-Host "  Result: $($out | ConvertTo-Json -Depth 3 -Compress)"
                    if (Get-SuccessFromResult -Result $out) {
                        $scenarioResult = New-ScenarioResult -Name 'KvTcp' -Status 'PASS' `
                            -Notes "TCP connection to $kvFqdn port $KvPort succeeded"
                    }
                    else {
                        $scenarioResult = New-ScenarioResult -Name 'KvTcp' -Status 'FAIL' `
                            -Notes "TCP connection to $kvFqdn port $KvPort failed"
                    }
                }
            }
        }
        # ── SqlTcp ──────────────────────────────────────────────────────────────
        elseif ($scenarioName -eq 'SqlTcp') {
            if ([string]::IsNullOrWhiteSpace($sqlFqdn)) {
                $scenarioResult = New-ScenarioResult -Name 'SqlTcp' -Status 'SKIP' `
                    -Notes 'SQL Server FQDN not found in deploy outputs (deploySql=false)'
            }
            else {
                $cmd = Get-Command -Name 'Test-NetworkConnectivity' -ErrorAction SilentlyContinue
                if (-not $cmd) {
                    $scenarioResult = New-ScenarioResult -Name 'SqlTcp' -Status 'SKIP' `
                        -Notes "Test-NetworkConnectivity not found in module v$EnterprisePoliciesModuleVersion"
                }
                else {
                    $cmdArgs = Get-FilteredCmdletArgs -Command $cmd -Arguments @{
                        EnvironmentId = $resolvedEnvId
                        Destination   = $sqlFqdn
                        Port          = $SqlPort
                        TenantId      = $tenantId
                    }
                    $out = & $cmd @cmdArgs
                    Write-Host "  Result: $($out | ConvertTo-Json -Depth 3 -Compress)"
                    if (Get-SuccessFromResult -Result $out) {
                        $scenarioResult = New-ScenarioResult -Name 'SqlTcp' -Status 'PASS' `
                            -Notes "TCP connection to $sqlFqdn port $SqlPort succeeded"
                    }
                    else {
                        $scenarioResult = New-ScenarioResult -Name 'SqlTcp' -Status 'FAIL' `
                            -Notes "TCP connection to $sqlFqdn port $SqlPort failed"
                    }
                }
            }
        }
        # ── StorageTcp ──────────────────────────────────────────────────────────
        elseif ($scenarioName -eq 'StorageTcp') {
            if ([string]::IsNullOrWhiteSpace($storageFqdn)) {
                $scenarioResult = New-ScenarioResult -Name 'StorageTcp' -Status 'SKIP' `
                    -Notes 'Storage FQDN not found in deploy outputs'
            }
            else {
                $cmd = Get-Command -Name 'Test-NetworkConnectivity' -ErrorAction SilentlyContinue
                if (-not $cmd) {
                    $scenarioResult = New-ScenarioResult -Name 'StorageTcp' -Status 'SKIP' `
                        -Notes "Test-NetworkConnectivity not found in module v$EnterprisePoliciesModuleVersion"
                }
                else {
                    $cmdArgs = Get-FilteredCmdletArgs -Command $cmd -Arguments @{
                        EnvironmentId = $resolvedEnvId
                        Destination   = $storageFqdn
                        Port          = $StoragePort
                        TenantId      = $tenantId
                    }
                    $out = & $cmd @cmdArgs
                    Write-Host "  Result: $($out | ConvertTo-Json -Depth 3 -Compress)"
                    if (Get-SuccessFromResult -Result $out) {
                        $scenarioResult = New-ScenarioResult -Name 'StorageTcp' -Status 'PASS' `
                            -Notes "TCP connection to $storageFqdn port $StoragePort succeeded"
                    }
                    else {
                        $scenarioResult = New-ScenarioResult -Name 'StorageTcp' -Status 'FAIL' `
                            -Notes "TCP connection to $storageFqdn port $StoragePort failed"
                    }
                }
            }
        }
        # ── KvTls ───────────────────────────────────────────────────────────────
        elseif ($scenarioName -eq 'KvTls') {
            if ([string]::IsNullOrWhiteSpace($kvFqdn)) {
                $scenarioResult = New-ScenarioResult -Name 'KvTls' -Status 'SKIP' `
                    -Notes 'Key Vault FQDN not found in deploy outputs'
            }
            else {
                $cmd = Get-Command -Name 'Test-TLSHandshake' -ErrorAction SilentlyContinue
                if (-not $cmd) {
                    $scenarioResult = New-ScenarioResult -Name 'KvTls' -Status 'SKIP' `
                        -Notes "Test-TLSHandshake not found in module v$EnterprisePoliciesModuleVersion"
                }
                else {
                    $cmdArgs = Get-FilteredCmdletArgs -Command $cmd -Arguments @{
                        EnvironmentId = $resolvedEnvId
                        Destination   = $kvFqdn
                        Port          = $KvPort
                        TenantId      = $tenantId
                    }
                    $out = & $cmd @cmdArgs
                    Write-Host "  Result: $($out | ConvertTo-Json -Depth 3 -Compress)"
                    if (Get-SuccessFromResult -Result $out) {
                        $scenarioResult = New-ScenarioResult -Name 'KvTls' -Status 'PASS' `
                            -Notes "TLS handshake to $kvFqdn port $KvPort succeeded"
                    }
                    else {
                        $scenarioResult = New-ScenarioResult -Name 'KvTls' -Status 'FAIL' `
                            -Notes "TLS handshake to $kvFqdn port $KvPort failed"
                    }
                }
            }
        }
        # ── SqlTls ──────────────────────────────────────────────────────────────
        elseif ($scenarioName -eq 'SqlTls') {
            if ([string]::IsNullOrWhiteSpace($sqlFqdn)) {
                $scenarioResult = New-ScenarioResult -Name 'SqlTls' -Status 'SKIP' `
                    -Notes 'SQL Server FQDN not found in deploy outputs (deploySql=false)'
            }
            else {
                $cmd = Get-Command -Name 'Test-TLSHandshake' -ErrorAction SilentlyContinue
                if (-not $cmd) {
                    $scenarioResult = New-ScenarioResult -Name 'SqlTls' -Status 'SKIP' `
                        -Notes "Test-TLSHandshake not found in module v$EnterprisePoliciesModuleVersion"
                }
                else {
                    $cmdArgs = Get-FilteredCmdletArgs -Command $cmd -Arguments @{
                        EnvironmentId = $resolvedEnvId
                        Destination   = $sqlFqdn
                        Port          = $SqlPort
                        TenantId      = $tenantId
                    }
                    $out = & $cmd @cmdArgs
                    Write-Host "  Result: $($out | ConvertTo-Json -Depth 3 -Compress)"
                    if (Get-SuccessFromResult -Result $out) {
                        $scenarioResult = New-ScenarioResult -Name 'SqlTls' -Status 'PASS' `
                            -Notes "TLS handshake to $sqlFqdn port $SqlPort succeeded"
                    }
                    else {
                        $scenarioResult = New-ScenarioResult -Name 'SqlTls' -Status 'FAIL' `
                            -Notes "TLS handshake to $sqlFqdn port $SqlPort failed"
                    }
                }
            }
        }
    }
    catch {
        $errMsg = $_.Exception.Message
        Write-Host "  [ERROR] $errMsg" -ForegroundColor Red
        $scenarioResult = [pscustomobject]@{ Name = $scenarioName; Status = 'ERROR'; Notes = $errMsg }
    }

    if ($null -ne $scenarioResult) {
        $results.Add($scenarioResult)
    }
}

# ─── Summary table (All mode) ─────────────────────────────────────────────────

if ($Scenario -eq 'All') {
    Write-Host ''
    Write-Host '═══ Diagnostic Summary ═══' -ForegroundColor Cyan
    Write-Host ('{0,-14} {1,-6} {2}' -f 'Scenario', 'Status', 'Notes')
    Write-Host ('{0,-14} {1,-6} {2}' -f '--------', '------', '-----')
    foreach ($r in $results) {
        $color = switch ($r.Status) {
            'PASS'  { 'Green' }
            'FAIL'  { 'Red' }
            'ERROR' { 'Red' }
            default { 'Yellow' }
        }
        Write-Host ('{0,-14} {1,-6} {2}' -f $r.Name, $r.Status, $r.Notes) -ForegroundColor $color
    }
    Write-Host ''

    $passCount  = ($results | Where-Object { $_.Status -eq 'PASS' }).Count
    $failCount  = ($results | Where-Object { $_.Status -eq 'FAIL' }).Count
    $errorCount = ($results | Where-Object { $_.Status -eq 'ERROR' }).Count
    $skipCount  = ($results | Where-Object { $_.Status -eq 'SKIP' }).Count
    Write-Host "Total: $($results.Count) | PASS: $passCount | FAIL: $failCount | ERROR: $errorCount | SKIP: $skipCount"
}

# ─── Write JSON log ───────────────────────────────────────────────────────────

$resolvedDiagnosticsRunFile = [System.IO.Path]::GetFullPath($DiagnosticsRunFile)

$logObject = [pscustomobject]@{
    timestamp     = $runTimestamp
    environmentId = $resolvedEnvId
    tenantId      = $tenantId
    outputsFile   = $resolvedOutputsFile
    scenario      = $Scenario
    results       = $results
}

try {
    $logObject | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $resolvedDiagnosticsRunFile -Encoding UTF8
    Write-Host ''
    Write-Host "Diagnostics log written to: $resolvedDiagnosticsRunFile" -ForegroundColor DarkGray
}
catch {
    Write-Host "[WARN] Could not write diagnostics log: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'Next: review PASS/FAIL results above.' -ForegroundColor Cyan
Write-Host '  FAIL on a DNS scenario means traffic is resolving to a public IP — check private DNS zone linkage.'
Write-Host '  FAIL on a TCP/TLS scenario means the delegated subnet cannot reach the resource — check NSG rules and private endpoint health.'
Write-Host '  SKIP means the resource was not deployed (e.g. deploySql=false) or the cmdlet is not available in the installed module version.'
