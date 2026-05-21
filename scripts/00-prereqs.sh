#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose: Validate local prerequisites and Azure subscription readiness for the demo lab.
# Usage: ./scripts/00-prereqs.sh
# Args: none

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
RESET='\033[0m'
MIN_AZ_VERSION='2.60.0'
MIN_PWSH_VERSION='7.0.0'
PP_FEATURE_NAMESPACE='Microsoft.PowerPlatform'
PP_FEATURE_RESOURCE_TYPE='Microsoft.PowerPlatform/accounts/enterprisePolicies'
PP_FEATURE_NAME='enterprisePoliciesPreview'
NSP_FEATURE_NAMESPACE='Microsoft.Network'
NSP_FEATURE_NAME='AllowNSPInPublicPreview'
WAIT_TIMEOUT_SECONDS=900

ok() {
  echo -e "${GREEN}✓ $*${RESET}"
}

warn() {
  echo -e "${YELLOW}! $*${RESET}"
}

fail() {
  echo -e "${RED}✗ $*${RESET}" >&2
}

on_error() {
  local exit_code=$?
  fail "Command failed (exit ${exit_code}) at line ${1}: ${2}"
  exit "$exit_code"
}

trap 'on_error "${LINENO}" "${BASH_COMMAND}"' ERR

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    fail "Missing required tool: ${command_name}"
    exit 1
  fi
}

version_gte() {
  local actual="$1"
  local minimum="$2"
  [[ "$(printf '%s\n%s\n' "$minimum" "$actual" | sort -V | head -n 1)" == "$minimum" ]]
}

assert_min_version() {
  local display_name="$1"
  local actual_version="$2"
  local minimum_version="$3"

  if ! version_gte "$actual_version" "$minimum_version"; then
    fail "${display_name} ${minimum_version}+ is required. Found ${actual_version}."
    exit 1
  fi
}

get_bicep_version() {
  local output version

  output="$(az bicep version 2>&1 || true)"
  version="$(grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' <<<"$output" | head -n 1 || true)"
  if [[ -z "$version" ]]; then
    fail "Azure CLI Bicep CLI is not available. Run 'az bicep install' and rerun this script."
    exit 1
  fi

  printf '%s\n' "$version"
}

wait_for_provider() {
  local namespace="$1"
  local state=""
  local deadline=$((SECONDS + WAIT_TIMEOUT_SECONDS))

  while (( SECONDS < deadline )); do
    state="$(az provider show --namespace "$namespace" --query registrationState -o tsv 2>/dev/null || true)"
    if [[ "$state" == "Registered" ]]; then
      ok "Resource provider registered: ${namespace}"
      return 0
    fi

    echo "Waiting for provider ${namespace} to register (current state: ${state:-unknown})..."
    sleep 10
  done

  fail "Timed out waiting for resource provider ${namespace} to register."
  exit 1
}

wait_for_feature() {
  local namespace="$1"
  local feature_name="$2"
  local state=""
  local deadline=$((SECONDS + WAIT_TIMEOUT_SECONDS))

  while (( SECONDS < deadline )); do
    state="$(az feature show --namespace "$namespace" --name "$feature_name" --query properties.state -o tsv 2>/dev/null || true)"
    if [[ "$state" == "Registered" ]]; then
      ok "Subscription feature registered: ${namespace}/${feature_name}"
      return 0
    fi

    echo "Waiting for feature ${namespace}/${feature_name} to register (current state: ${state:-unknown})..."
    sleep 15
  done

  fail "Timed out waiting for feature ${namespace}/${feature_name} to register."
  exit 1
}

register_provider_if_needed() {
  local namespace="$1"
  local state=""

  state="$(az provider show --namespace "$namespace" --query registrationState -o tsv 2>/dev/null || true)"
  if [[ "$state" == "Registered" ]]; then
    ok "Resource provider already registered: ${namespace}"
    return 1
  fi

  echo "Registering resource provider ${namespace} (current state: ${state:-unknown})..."
  az provider register --namespace "$namespace" >/dev/null
  wait_for_provider "$namespace"
  return 0
}

register_feature_if_needed() {
  local namespace="$1"
  local feature_name="$2"
  local state=""

  state="$(az feature show --namespace "$namespace" --name "$feature_name" --query properties.state -o tsv 2>/dev/null || true)"
  case "$state" in
    Registered)
      ok "Subscription feature already registered: ${namespace}/${feature_name}"
      return 1
      ;;
    Registering|Pending)
      echo "Feature ${namespace}/${feature_name} is already in progress (current state: ${state}). Waiting for completion..."
      wait_for_feature "$namespace" "$feature_name"
      return 0
      ;;
    *)
      echo "Registering subscription feature ${namespace}/${feature_name} (current state: ${state:-unknown})..."
      az feature register --namespace "$namespace" --name "$feature_name" >/dev/null
      wait_for_feature "$namespace" "$feature_name"
      return 0
      ;;
  esac
}

main() {
  local account_json subscription_name subscription_id tenant_id
  local az_version bicep_version pwsh_version jq_version bash_version
  local nsp_feature_changed=false
  local providers=(
    'Microsoft.PowerPlatform'
    'Microsoft.Sql'
    'Microsoft.KeyVault'
    'Microsoft.Storage'
    'Microsoft.Network'
    'Microsoft.Insights'
  )

  require_command az
  require_command pwsh
  require_command jq

  az_version="$(az version -o json | jq -r '."azure-cli"')"
  bicep_version="$(get_bicep_version)"
  pwsh_version="$(pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()')"
  jq_version="$(jq --version | sed 's/^jq-//')"
  bash_version="${BASH_VERSION%%(*}"

  assert_min_version 'Azure CLI' "$az_version" "$MIN_AZ_VERSION"
  assert_min_version 'PowerShell' "$pwsh_version" "$MIN_PWSH_VERSION"

  ok "az version: ${az_version}"
  ok "bicep version: ${bicep_version}"
  ok "pwsh version: ${pwsh_version}"
  ok "jq version: ${jq_version}"
  ok "bash version: ${bash_version}"

  if ! account_json="$(az account show -o json 2>/dev/null)"; then
    fail "Azure CLI is not signed in. Run 'az login' and rerun this script."
    exit 1
  fi

  subscription_name="$(jq -r '.name' <<<"$account_json")"
  subscription_id="$(jq -r '.id' <<<"$account_json")"
  tenant_id="$(jq -r '.tenantId' <<<"$account_json")"

  ok 'Azure session is active'
  echo "Subscription: ${subscription_name} (${subscription_id})"
  echo "Tenant:       ${tenant_id}"

  for provider in "${providers[@]}"; do
    register_provider_if_needed "$provider" || true
  done

  echo "Ensuring preview feature ${PP_FEATURE_NAME} is registered for ${PP_FEATURE_RESOURCE_TYPE}..."
  register_feature_if_needed "$PP_FEATURE_NAMESPACE" "$PP_FEATURE_NAME" || true

  echo "Ensuring NSP preview feature ${NSP_FEATURE_NAMESPACE}/${NSP_FEATURE_NAME} is registered..."
  if register_feature_if_needed "$NSP_FEATURE_NAMESPACE" "$NSP_FEATURE_NAME"; then
    nsp_feature_changed=true
  fi

  if [[ "$nsp_feature_changed" == true ]]; then
    echo "Refreshing ${NSP_FEATURE_NAMESPACE} provider registration after feature enablement..."
    az provider register --namespace "$NSP_FEATURE_NAMESPACE" >/dev/null
    wait_for_provider "$NSP_FEATURE_NAMESPACE"
  else
    ok "No ${NSP_FEATURE_NAME} refresh needed; ${NSP_FEATURE_NAMESPACE} feature already active."
  fi

  ok 'Prerequisites completed successfully'
  echo
  echo "Summary: validated az ${MIN_AZ_VERSION}+, pwsh ${MIN_PWSH_VERSION}+, bicep, jq, and bash; verified provider registrations for Microsoft.PowerPlatform, Microsoft.Sql, Microsoft.KeyVault, Microsoft.Storage, Microsoft.Network, and Microsoft.Insights; enabled ${PP_FEATURE_NAME} for ${PP_FEATURE_RESOURCE_TYPE}; ensured ${NSP_FEATURE_NAMESPACE}/${NSP_FEATURE_NAME} is active for NSP preview deployments."
  echo 'Next: run ./scripts/01-deploy.sh'
  warn 'Network diagnostics: after deployment and subnet injection are complete, run `pwsh ./scripts/06-network-diagnostics.ps1 -Scenario All` to validate the VNet path end-to-end.'
  warn 'Microsoft.NetworkAnalytics is not required; Traffic Analytics auto-provisions its NetworkMonitoring solution and AzureNetworkAnalytics_CL data path after the first processed flow-log batch.'
  warn 'If a shell script still fails in your environment, verify it is checked out with LF line endings and executable permissions.'
}

main "$@"
