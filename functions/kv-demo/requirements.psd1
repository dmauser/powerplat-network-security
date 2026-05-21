# requirements.psd1 — managed dependency manifest for Azure Functions PowerShell runtime.
#
# This function uses raw REST calls to Key Vault via Invoke-RestMethod (IMDS token acquisition
# + KV REST API). No Az.KeyVault module import is required, which keeps cold-start latency low
# and ensures outbound HTTP calls are auto-tracked as App Insights dependencies.
#
# If you switch run.ps1 to the Az.KeyVault SDK path, uncomment below and re-add
# Connect-AzAccount -Identity to profile.ps1.
#
# @{
#     'Az.KeyVault' = '6.*'
# }

@{}
