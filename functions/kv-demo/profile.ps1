# profile.ps1 — executed once at cold start before any function runs.
#
# This profile is intentionally minimal: run.ps1 uses raw REST (Invoke-RestMethod) with
# an IMDS-issued managed-identity token, so no Az module import or Connect-AzAccount call
# is needed. Keeping this file lean reduces cold-start latency.
#
# If the function ever needs Az cmdlets, add:
#   if ($env:MSI_ENDPOINT) { Connect-AzAccount -Identity }

# No-op — cold start optimised.
