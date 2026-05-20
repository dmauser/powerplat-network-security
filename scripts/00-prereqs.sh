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
FEATURE_NAMESPACE='Microsoft.PowerPlatform'
FEATURE_RESOURCE_TYPE='Microsoft.PowerPlatform/accounts/enterprisePolicies'
FEATURE_NAME='enterprisePoliciesPreview'
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

main() {
  local account_json subscription_name subscription_id tenant_id
  local az_version bicep_version pwsh_version jq_version bash_version
  local providers=(
    'Microsoft.PowerPlatform'
    'Microsoft.Sql'
    'Microsoft.KeyVault'
    'Microsoft.Storage'
    'Microsoft.Network'
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
    echo "Ensuring resource provider ${provider} is registered..."
    az provider register --namespace "$provider" --wait >/dev/null
    wait_for_provider "$provider"
  done

  echo "Ensuring preview feature ${FEATURE_NAME} is registered for ${FEATURE_RESOURCE_TYPE}..."
  az feature register --namespace "$FEATURE_NAMESPACE" --name "$FEATURE_NAME" >/dev/null
  wait_for_feature "$FEATURE_NAMESPACE" "$FEATURE_NAME"

  echo "Refreshing ${FEATURE_NAMESPACE} provider registration after feature enablement..."
  az provider register --namespace "$FEATURE_NAMESPACE" --wait >/dev/null
  wait_for_provider "$FEATURE_NAMESPACE"

  ok 'Prerequisites completed successfully'
  echo
  echo "Summary: validated az ${MIN_AZ_VERSION}+, pwsh ${MIN_PWSH_VERSION}+, bicep, jq, and bash; registered the required resource providers; enabled ${FEATURE_NAME} for ${FEATURE_RESOURCE_TYPE}."
  echo 'Next: run ./scripts/01-deploy.sh'
  warn 'If a shell script still fails in your environment, verify it is checked out with LF line endings and executable permissions.'
}

main "$@"
