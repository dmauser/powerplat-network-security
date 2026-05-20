#!/usr/bin/env bash
set -euo pipefail

# Purpose: Validate local prerequisites and Azure subscription readiness for the demo lab.
# Usage: ./scripts/00-prereqs.sh
# Args: none

GREEN='\033[1;32m'
RED='\033[1;31m'
RESET='\033[0m'

ok() {
  echo -e "${GREEN}✓ $*${RESET}"
}

fail() {
  echo -e "${RED}✗ $*${RESET}" >&2
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    fail "Missing required tool: ${command_name}"
    exit 1
  fi
}

wait_for_provider() {
  local namespace="$1"
  local state=""

  while true; do
    state="$(az provider show --namespace "$namespace" --query registrationState -o tsv 2>/dev/null || true)"
    if [[ "$state" == "Registered" ]]; then
      ok "Resource provider registered: ${namespace}"
      return 0
    fi

    echo "Waiting for provider ${namespace} to register (current state: ${state:-unknown})..."
    sleep 10
  done
}

wait_for_feature() {
  local namespace="$1"
  local feature_name="$2"
  local state=""

  while true; do
    state="$(az feature show --namespace "$namespace" --name "$feature_name" --query properties.state -o tsv 2>/dev/null || true)"
    if [[ "$state" == "Registered" ]]; then
      ok "Subscription feature registered: ${namespace}/${feature_name}"
      return 0
    fi

    echo "Waiting for feature ${namespace}/${feature_name} to register (current state: ${state:-unknown})..."
    sleep 15
  done
}

main() {
  local account_json subscription_name subscription_id tenant_id cli_version bicep_version
  local providers=(
    "Microsoft.Network"
    "Microsoft.PowerPlatform"
    "Microsoft.KeyVault"
    "Microsoft.Sql"
    "Microsoft.Storage"
    "Microsoft.ManagedIdentity"
    "Microsoft.Authorization"
  )

  require_command az
  require_command pwsh
  require_command jq

  cli_version="$(az version -o json | jq -r '."azure-cli"')"
  bicep_version="$(az bicep version 2>&1 | tail -n 1)"
  ok "az version: ${cli_version}"
  ok "bicep version: ${bicep_version}"
  ok "pwsh version: $(pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()')"
  ok "jq version: $(jq --version)"

  if ! account_json="$(az account show -o json 2>/dev/null)"; then
    fail "Azure CLI is not signed in. Run 'az login' and rerun this script."
    exit 1
  fi

  subscription_name="$(jq -r '.name' <<<"$account_json")"
  subscription_id="$(jq -r '.id' <<<"$account_json")"
  tenant_id="$(jq -r '.tenantId' <<<"$account_json")"

  ok "Azure session is active"
  echo "Subscription: ${subscription_name} (${subscription_id})"
  echo "Tenant:       ${tenant_id}"

  for provider in "${providers[@]}"; do
    echo "Registering resource provider ${provider}..."
    az provider register --namespace "$provider" --wait >/dev/null
    wait_for_provider "$provider"
  done

  echo "Registering subscription feature Microsoft.PowerPlatform/enterprisePoliciesPreview..."
  az feature register --namespace Microsoft.PowerPlatform --name enterprisePoliciesPreview >/dev/null
  wait_for_feature "Microsoft.PowerPlatform" "enterprisePoliciesPreview"

  ok "Prerequisites completed successfully"
  echo
  echo "Summary: Azure CLI access is valid, required providers are registered, and enterprisePoliciesPreview is enabled."
  echo "Next: run ./scripts/01-deploy.sh"
  echo "Note: remember to chmod +x scripts/*.sh (and later git update-index --chmod=+x for tracked shell scripts)."
}

main "$@"
