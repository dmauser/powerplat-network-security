#requires -Version 7.0
<#
.SYNOPSIS
Configures Power Platform VNet subnet injection for a target environment using the latest deployment outputs.

.DESCRIPTION
Reads the enterprise policy ARM ID from .azure/last-deploy-outputs.json, validates the environment region,
and enables subnet injection for the supplied Power Platform environment.

.PARAMETER EnvironmentId
Power Platform environment GUID.

.PARAMETER TenantId
Optional tenant ID. Defaults to the current Azure CLI tenant.

.PARAMETER DeployOutputsPath
Path to the deployment outputs JSON file. Default: .azure/last-deploy-outputs.json

.PARAMETER ForceAuth
Passes -ForceAuth to Enable-SubnetInjection when specified.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentId,

    [Parameter()]
    [string]$TenantId,

    [Parameter()]
    [string]$DeployOutputsPath = '.azure/last-deploy-outputs.json',

    [Parameter()]
    [switch]$ForceAuth
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Show-FixupSteps {
    Write-Host ''
    Write-Host 'Fix-up steps:' -ForegroundColor Yellow
    Write-Host '  1. Confirm Azure CLI is signed in: az login'
    Write-Host '  2. Confirm the target Power Platform environment exists and the GUID is correct.'
    Write-Host '  3. Confirm the environment region is United States for this preview scenario.'
    Write-Host '  4. If module install/auth prompts were interrupted, rerun with -ForceAuth.'
    Write-Host '  5. Make sure .azure/last-deploy-outputs.json exists from ./scripts/01-deploy.sh.'
}

function Install-RequiredModule {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not (Get-Module -ListAvailable -Name $Name)) {
        Write-Host "Installing PowerShell module $Name..."
        Install-Module -Name $Name -Force -Scope CurrentUser -AllowClobber
    }

    Import-Module -Name $Name -Force
}

function Get-CurrentTenantId {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'Azure CLI (az) is required to resolve the current tenant ID.'
    }

    $currentTenantId = az account show --query tenantId -o tsv 2>$null
    if (-not $currentTenantId) {
        throw 'Unable to resolve the current tenant ID. Run az login and retry.'
    }

    return $currentTenantId.Trim()
}

function Get-RegionText {
    param(
        [Parameter(Mandatory = $true)]
        [object]$RegionResult
    )

    if ($RegionResult -is [string]) {
        return $RegionResult
    }

    foreach ($propertyName in 'Region', 'region', 'Name', 'name', 'Location', 'location') {
        if ($RegionResult.PSObject.Properties.Name -contains $propertyName) {
            return [string]$RegionResult.$propertyName
        }
    }

    return [string]$RegionResult
}

try {
    if (-not $TenantId) {
        $TenantId = Get-CurrentTenantId
    }

    if (-not (Test-Path -LiteralPath $DeployOutputsPath)) {
        throw "Deployment outputs file not found: $DeployOutputsPath"
    }

    $deployOutputs = Get-Content -LiteralPath $DeployOutputsPath -Raw | ConvertFrom-Json
    $policyArmId = $deployOutputs.enterprisePolicyArmId.value
    if (-not $policyArmId) {
        throw 'enterprisePolicyArmId.value was not found in the deployment outputs JSON.'
    }

    Install-RequiredModule -Name 'Microsoft.PowerPlatform.EnterprisePolicies'
    Install-RequiredModule -Name 'Microsoft.PowerPlatform.Administration.PowerShell'

    $regionCommand = Get-Command -Name 'Get-EnvironmentRegion' -ErrorAction SilentlyContinue
    if (-not $regionCommand) {
        throw 'Get-EnvironmentRegion is not available after importing the required modules.'
    }

    $regionArgs = @{
        EnvironmentId = $EnvironmentId
    }
    if ($regionCommand.Parameters.ContainsKey('TenantId')) {
        $regionArgs['TenantId'] = $TenantId
    }

    $regionResult = & $regionCommand @regionArgs
    $regionText = (Get-RegionText -RegionResult $regionResult).Trim().ToLowerInvariant()
    if ($regionText -ne 'unitedstates') {
        throw "Environment region mismatch. Expected 'unitedstates' but received '$regionText'."
    }

    $enableCommand = Get-Command -Name 'Enable-SubnetInjection' -ErrorAction Stop
    $enableArgs = @{
        EnvironmentId = $EnvironmentId
        PolicyArmId   = $policyArmId
    }
    if ($enableCommand.Parameters.ContainsKey('TenantId')) {
        $enableArgs['TenantId'] = $TenantId
    }
    if ($ForceAuth -and $enableCommand.Parameters.ContainsKey('ForceAuth')) {
        $enableArgs['ForceAuth'] = $true
    }

    Write-Host "Using tenant ID: $TenantId"
    Write-Host "Applying enterprise policy: $policyArmId"
    & $enableCommand @enableArgs | Out-Null

    Write-Host ''
    Write-Host 'Power Platform VNet configuration completed successfully.' -ForegroundColor Green
    Write-Host "Environment ID            : $EnvironmentId"
    Write-Host "Tenant ID                 : $TenantId"
    Write-Host "Enterprise policy ARM ID  : $policyArmId"
    Write-Host ''
    Write-Host 'Connector setup hints:'
    Write-Host '  - Use the built-in Azure Key Vault connector -> see docs/connectors/keyvault.md'
    Write-Host '  - Use the SQL Server connector -> see docs/connectors/sql.md'
    Write-Host '  - Use the Azure Blob Storage connector -> see docs/connectors/blob.md'
    Write-Host '  - Or build a custom connector -> see docs/connectors/custom-http.md'
}
catch {
    Write-Error $_
    Show-FixupSteps
    exit 1
}
