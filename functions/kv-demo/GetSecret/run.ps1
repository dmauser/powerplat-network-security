using namespace System.Net

# HTTP trigger — GetSecret
# Reads demo-secret from East Key Vault via the Function App's system-assigned managed identity.
# Uses raw REST (IMDS token + KV REST API) so that Invoke-RestMethod calls are auto-captured
# as outbound dependencies in Application Insights (dependencies table, target = *.vault.azure.net).
#
# Environment variables (set by Bicep):
#   KEY_VAULT_NAME  — e.g. kv-pbinet-dev-k6ozyjreme
#   REGION          — e.g. east | west
#   SECRET_NAME     — e.g. demo-secret (defaults to 'demo-secret' if not set)

param($Request, $TriggerMetadata)

$kvName    = $env:KEY_VAULT_NAME
$region    = $env:REGION
$secretName = if ($env:SECRET_NAME) { $env:SECRET_NAME } else { 'demo-secret' }

if (-not $kvName) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body       = (ConvertTo-Json @{ error = 'KEY_VAULT_NAME env var not set'; region = $region })
        Headers    = @{ 'Content-Type' = 'application/json' }
    })
    return
}

$kvHost = "${kvName}.vault.azure.net"

try {
    # Step 1: Acquire managed-identity token from IMDS.
    # resource=https://vault.azure.net is the KV audience (no trailing slash).
    Write-Information "Acquiring MI token for vault.azure.net from IMDS"
    $tokenUri = 'http://169.254.169.254/metadata/identity/oauth2/token' +
                '?api-version=2018-02-01&resource=https://vault.azure.net'
    $tokenResponse = Invoke-RestMethod -Uri $tokenUri `
                                       -Headers @{ Metadata = 'true' } `
                                       -Method Get
    $accessToken = $tokenResponse.access_token

    # Step 2: Fetch the secret from KV REST API.
    # Invoke-RestMethod is auto-tracked by App Insights as an outbound dependency
    # (target = kv-pbinet-dev-k6ozyjreme.vault.azure.net) — this populates the
    # dependencies table and closes the Part 4 gap.
    $secretUri = "https://${kvHost}/secrets/${secretName}?api-version=7.4"
    Write-Information "Fetching secret from ${secretUri}"
    $secretResponse = Invoke-RestMethod -Uri $secretUri `
                                        -Headers @{ Authorization = "Bearer $accessToken" } `
                                        -Method Get

    $body = ConvertTo-Json @{
        region          = $region
        secretFetchedOk = $true
        kvHost          = $kvHost
        timestamp       = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
        Headers    = @{ 'Content-Type' = 'application/json' }
    })
}
catch {
    $errMsg = $_.Exception.Message
    Write-Error "GetSecret failed: ${errMsg}"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body       = (ConvertTo-Json @{
            region          = $region
            secretFetchedOk = $false
            kvHost          = $kvHost
            error           = $errMsg
            timestamp       = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        })
        Headers    = @{ 'Content-Type' = 'application/json' }
    })
}
