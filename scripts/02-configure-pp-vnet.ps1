#requires -Version 7.0
<#
.SYNOPSIS
Configures Power Platform VNet subnet injection for a target environment using the latest deployment outputs.

.DESCRIPTION
Reads the enterprise policy ARM ID from .azure/last-deploy-outputs.json, validates the environment region,
and enables subnet injection for the supplied Power Platform environment.

.PARAMETER EnvironmentId
Power Platform environment ID.

.PARAMETER TenantId
Optional tenant ID. Defaults to the current Azure CLI tenant.

.PARAMETER DeployOutputsPath
Optional path to the deployment outputs JSON file. Defaults to ..\.azure\last-deploy-outputs.json relative to this script.

.PARAMETER ForceAuth
Passes -ForceAuth to the Microsoft.PowerPlatform.EnterprisePolicies commands when specified.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrWhiteSpace()]
    [string]$EnvironmentId,

    [Parameter()]
    [ValidateNotNullOrWhiteSpace()]
    [string]$TenantId,

    [Parameter()]
    [string]$DeployOutputsPath,

    [Parameter()]
    [switch]$ForceAuth
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$EnterprisePoliciesModuleVersion = '0.17.0'
$AllowedRegionTokens = @('unitedstates', 'eastus', 'westus')
$DefaultDeployOutputsPath = Join-Path -Path $PSScriptRoot -ChildPath '..\.azure\last-deploy-outputs.json'
$ResolvedDeployOutputsPath = $DefaultDeployOutputsPath

function Show-FixupSteps {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeployOutputsFile
    )

    Write-Host ''
    Write-Host 'Fix-up steps:' -ForegroundColor Yellow
    Write-Host '  1. Confirm Azure CLI is signed in: az login'
    Write-Host '  2. Confirm the target Power Platform environment exists and the environment ID is correct.'
    Write-Host '  3. Confirm the environment is a Managed Environment in the United States geography.'
    Write-Host '  4. Confirm ./scripts/01-deploy.sh already produced the deploy outputs file listed below.'
    Write-Host "  5. If account selection or module install was interrupted, rerun this script with -ForceAuth."
    Write-Host "  6. Expected deploy outputs path: $DeployOutputsFile"
}

function Show-NextSteps {
    Write-Host ''
    Write-Host 'Next steps:' -ForegroundColor Cyan
    Write-Host '  1. Run ./scripts/03-validate-network.sh'
    Write-Host '  2. Test the connector walkthroughs in docs/connectors/keyvault.md, sql.md, blob.md, and custom-http.md'
}

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
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequiredVersion
    )

    $availableModule = Get-Module -ListAvailable -Name 'Microsoft.PowerPlatform.EnterprisePolicies' |
        Where-Object { $_.Version -eq [version]$RequiredVersion } |
        Select-Object -First 1

    if (-not $availableModule) {
        Write-Host "Installing Microsoft.PowerPlatform.EnterprisePolicies $RequiredVersion for the current user..."
        Install-Module -Name 'Microsoft.PowerPlatform.EnterprisePolicies' -RequiredVersion $RequiredVersion -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    }

    Import-Module -Name 'Microsoft.PowerPlatform.EnterprisePolicies' -RequiredVersion $RequiredVersion -Force -ErrorAction Stop
}

function Get-ResolvedDeployOutputsPath {
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return [System.IO.Path]::GetFullPath($DefaultDeployOutputsPath)
    }

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location) -ChildPath $Path))
}

function Get-CurrentTenantId {
    Assert-CommandAvailable -Name 'az'

    $currentTenantId = az account show --query tenantId -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($currentTenantId)) {
        throw 'Unable to resolve the current tenant ID. Run az login and retry.'
    }

    return $currentTenantId.Trim()
}

function Get-DeployOutputs {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Deployment outputs file not found: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
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

function Get-NormalizedRegionToken {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RegionText
    )

    return ($RegionText.ToLowerInvariant() -replace '[^a-z0-9]', '')
}

function Get-PolicyArmIdValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject
    )

    foreach ($propertyName in 'ResourceId', 'resourceId', 'Id', 'id') {
        if ($InputObject.PSObject.Properties.Name -contains $propertyName) {
            $value = [string]$InputObject.$propertyName
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                return $value
            }
        }
    }

    return $null
}

function Get-EnterprisePoliciesCommandArguments {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.CommandInfo]$Command,
        [Parameter(Mandatory = $true)]
        [hashtable]$Arguments
    )

    $supportedArguments = @{}
    foreach ($entry in $Arguments.GetEnumerator()) {
        if ($Command.Parameters.ContainsKey($entry.Key)) {
            $supportedArguments[$entry.Key] = $entry.Value
        }
    }

    return $supportedArguments
}

function Get-CurrentLinkedPolicyArmId {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvironmentId,
        [Parameter(Mandatory = $true)]
        [string]$TenantId,
        [Parameter(Mandatory = $true)]
        [bool]$UseForceAuth
    )

    $command = Get-Command -Name 'Get-SubnetInjectionEnterprisePolicy' -ErrorAction Stop
    $commandArguments = Get-EnterprisePoliciesCommandArguments -Command $command -Arguments @{
        EnvironmentId = $EnvironmentId
        TenantId      = $TenantId
        ForceAuth     = $UseForceAuth
    }

    try {
        $currentPolicy = & $command @commandArguments
    }
    catch {
        if ($_.Exception.Message -like 'No Subnet Injection Enterprise Policy is linked to environment:*') {
            return $null
        }

        throw
    }

    return Get-PolicyArmIdValue -InputObject $currentPolicy
}

try {
    Assert-CommandAvailable -Name 'az'

    if (-not $PSBoundParameters.ContainsKey('TenantId')) {
        $TenantId = Get-CurrentTenantId
    }

    $ResolvedDeployOutputsPath = Get-ResolvedDeployOutputsPath -Path $DeployOutputsPath
    $deployOutputs = Get-DeployOutputs -Path $ResolvedDeployOutputsPath
    $policyArmId = [string]$deployOutputs.enterprisePolicyArmId.value
    if ([string]::IsNullOrWhiteSpace($policyArmId)) {
        throw 'enterprisePolicyArmId.value was not found in the deployment outputs JSON.'
    }

    if ($policyArmId -notmatch '/providers/Microsoft\.PowerPlatform/enterprisePolicies/') {
        throw "Deployment output enterprisePolicyArmId does not look like a Microsoft.PowerPlatform enterprise policy ARM ID: $policyArmId"
    }

    # Read optional Application Insights outputs from Bicep deploy (set when deployMonitoring=true).
    # If absent, the AI binding step is skipped with a warning.
    $appInsightsResourceId = [string]$deployOutputs.appInsightsResourceId.value
    $appInsightsConnectionString = [string]$deployOutputs.appInsightsConnectionString.value
    $appInsightsInstrumentationKey = [string]$deployOutputs.appInsightsInstrumentationKey.value

    Install-EnterprisePoliciesModule -RequiredVersion $EnterprisePoliciesModuleVersion

    $regionCommand = Get-Command -Name 'Get-EnvironmentRegion' -ErrorAction Stop
    $null = Get-Command -Name 'Get-SubnetInjectionEnterprisePolicy' -ErrorAction Stop
    $enableCommand = Get-Command -Name 'Enable-SubnetInjection' -ErrorAction Stop

    $regionArguments = Get-EnterprisePoliciesCommandArguments -Command $regionCommand -Arguments @{
        EnvironmentId = $EnvironmentId
        TenantId      = $TenantId
        ForceAuth     = $ForceAuth.IsPresent
    }

    $regionResult = & $regionCommand @regionArguments
    $regionText = (Get-RegionText -RegionResult $regionResult).Trim()
    $normalizedRegion = Get-NormalizedRegionToken -RegionText $regionText
    if ($AllowedRegionTokens -notcontains $normalizedRegion) {
        throw "Environment region mismatch. Expected the United States lab geography but received '$regionText'."
    }

    Write-Host "Using tenant ID           : $TenantId"
    Write-Host "Deploy outputs path       : $ResolvedDeployOutputsPath"
    Write-Host "Pinned module version     : $EnterprisePoliciesModuleVersion"
    Write-Host "Resolved environment geo  : $regionText"
    Write-Host "Target policy ARM ID      : $policyArmId"

    $currentPolicyArmId = Get-CurrentLinkedPolicyArmId -EnvironmentId $EnvironmentId -TenantId $TenantId -UseForceAuth:$ForceAuth.IsPresent
    if ($currentPolicyArmId) {
        Write-Host "Current linked policy     : $currentPolicyArmId"

        if ($currentPolicyArmId -ieq $policyArmId) {
            Write-Host ''
            Write-Host 'Power Platform VNet configuration already matches the requested policy. No changes were applied.' -ForegroundColor Yellow
            Write-Host "Environment ID            : $EnvironmentId"
            Show-NextSteps
            exit 0
        }

        throw "Environment already has a different subnet injection policy linked: $currentPolicyArmId. This script does not swap policies automatically. Use Enable-SubnetInjection -Swap intentionally if you mean to replace it."
    }

    $enableArguments = Get-EnterprisePoliciesCommandArguments -Command $enableCommand -Arguments @{
        EnvironmentId = $EnvironmentId
        PolicyArmId   = $policyArmId
        TenantId      = $TenantId
        ForceAuth     = $ForceAuth.IsPresent
    }

    $enableResult = & $enableCommand @enableArguments
    if ($enableResult -is [bool] -and -not $enableResult) {
        throw 'Enable-SubnetInjection returned False.'
    }

    Write-Host ''
    Write-Host 'Power Platform VNet configuration completed successfully.' -ForegroundColor Green
    Write-Host "Environment ID            : $EnvironmentId"
    Write-Host "Tenant ID                 : $TenantId"
    Write-Host "Enterprise policy ARM ID  : $policyArmId"

    # ---------------------------------------------------------------------------
    # Application Insights binding
    #
    # Set-AdminPowerAppEnvironmentApplicationInsights does not exist in
    # Microsoft.PowerPlatform.EnterprisePolicies v0.17.0 or
    # Microsoft.PowerApps.Administration.PowerShell. Fall back to the
    # Power Platform admin REST API.
    #
    # API: PATCH https://api.bap.microsoft.com/providers/
    #        Microsoft.BusinessAppPlatform/scopes/admin/environments/{id}
    #      ?api-version=2023-06-01
    # Body: { "properties": { "applicationInsightsId": "...",
    #                          "applicationInsightsKey": "<connectionString>" } }
    #
    # Reference: https://learn.microsoft.com/en-us/power-platform/admin/app-insights-overview
    # ---------------------------------------------------------------------------

    if ([string]::IsNullOrWhiteSpace($appInsightsResourceId)) {
        Write-Host ''
        Write-Host 'Application Insights outputs not found in deploy outputs — skipping AI binding.' -ForegroundColor Yellow
        Write-Host '  Deploy with deployMonitoring=true (and logAnalyticsWorkspaceId set) to enable.'
    }
    else {
        Write-Host ''
        Write-Host "Configuring Application Insights binding for environment $EnvironmentId ..."
        Write-Host "  App Insights resource ID : $appInsightsResourceId"

        # Acquire a Power Apps bearer token using the current Azure CLI session.
        $ppTokenResult = az account get-access-token --resource 'https://service.powerapps.com/' --output json 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($ppTokenResult)) {
            throw 'Unable to acquire a Power Apps bearer token. Ensure az login is complete and the account has PP admin rights.'
        }
        $ppToken = ($ppTokenResult | ConvertFrom-Json).accessToken

        $bapBase = 'https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments'
        $apiVersion = '2023-06-01'
        $envUri = "$bapBase/$([Uri]::EscapeDataString($EnvironmentId))?api-version=$apiVersion"

        $headers = @{
            Authorization  = "Bearer $ppToken"
            'Content-Type' = 'application/json'
        }

        # Read current binding for idempotency check.
        $currentEnv = Invoke-RestMethod -Uri $envUri -Method Get -Headers $headers -ErrorAction Stop
        $currentAiId = [string]$currentEnv.properties.applicationInsightsId

        if ($currentAiId -ieq $appInsightsResourceId) {
            Write-Host '  Application Insights already bound to this resource — no change applied.' -ForegroundColor Yellow
        }
        else {
            if (-not [string]::IsNullOrWhiteSpace($currentAiId)) {
                Write-Host "  Replacing existing AI binding: $currentAiId"
            }

            # Use connection string as the key value (modern PP telemetry pipeline).
            # The 'applicationInsightsKey' field accepts either the instrumentation key
            # (legacy) or the full connection string. The connection string is preferred
            # for workspace-based App Insights.
            $aiKeyValue = if (-not [string]::IsNullOrWhiteSpace($appInsightsConnectionString)) {
                $appInsightsConnectionString
            } else {
                $appInsightsInstrumentationKey
            }

            $patchBody = @{
                properties = @{
                    applicationInsightsId  = $appInsightsResourceId
                    applicationInsightsKey = $aiKeyValue
                }
            } | ConvertTo-Json -Depth 5 -Compress

            $null = Invoke-RestMethod -Uri $envUri -Method Patch -Headers $headers -Body $patchBody -ErrorAction Stop

            Write-Host '  Application Insights bound successfully.' -ForegroundColor Green
            Write-Host "  Resource ID : $appInsightsResourceId"
        }
    }

    Show-NextSteps
}
catch {
    Write-Error -Message $_.Exception.Message
    Show-FixupSteps -DeployOutputsFile $ResolvedDeployOutputsPath
    exit 1
}
