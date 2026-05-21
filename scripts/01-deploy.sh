#!/usr/bin/env bash
set -euo pipefail

# Purpose: Run the subscription-scope Bicep deployment and persist the latest outputs for follow-on scripts.
# Usage: ./scripts/01-deploy.sh [--what-if] [--parameters-file <path>] [--location <region>]
# Args:
#   --what-if                 Run az deployment sub what-if and exit.
#   --parameters-file <path>  Parameters file path. Default: infra/parameters/dev.parameters.json
#   --location <region>       Subscription deployment metadata location. Default: eastus
#   --demo-user-oid <oid>     Additional AAD user object ID granted Key Vault Secrets User on the demo
#                             vault. Repeat the flag for multiple users. Defaults to the current
#                             signed-in user (so the Power Apps KV connector can read demo-secret).
#   --no-auto-demo-user       Skip auto-adding the signed-in user to demoUserPrincipalIds.

GREEN='\033[1;32m'
RED='\033[1;31m'
RESET='\033[0m'

ok() {
  echo -e "${GREEN}✓ $*${RESET}"
}

fail() {
  echo -e "${RED}✗ $*${RESET}" >&2
}

usage() {
  sed -n '4,9p' "$0"
}

main() {
  local what_if=false
  local parameters_file="infra/parameters/dev.parameters.json"
  local location="eastus"
  local deployment_name
  local deploy_json outputs_file
  local enterprise_policy_arm_id key_vault_name key_vault_uri sql_server_fqdn sql_database_name storage_account_name uami_resource_id uami_principal_id
  local -a demo_user_oids=()
  local auto_demo_user=true
  local signed_in_oid demo_user_json

  if ! command -v az >/dev/null 2>&1; then
    fail 'Azure CLI (az) is required.'
    exit 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    fail 'jq is required.'
    exit 1
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --what-if)
        what_if=true
        shift
        ;;
      --parameters-file)
        parameters_file="$2"
        shift 2
        ;;
      --location)
        location="$2"
        shift 2
        ;;
      --demo-user-oid)
        demo_user_oids+=("$2")
        shift 2
        ;;
      --no-auto-demo-user)
        auto_demo_user=false
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
  done

  if [[ ! -f "$parameters_file" ]]; then
    fail "Parameters file not found: ${parameters_file}"
    exit 1
  fi

  if [[ ! -f "infra/main.bicep" ]]; then
    fail "Template file not found: infra/main.bicep"
    exit 1
  fi

  deployment_name="pp-vnet-kv-demo-$(date +%Y%m%d%H%M)"

  # Auto-include the signed-in user so the Power Apps Key Vault connector (per-user OAuth)
  # can read demo-secret from the VNet-injected Managed Environment.
  if [[ "$auto_demo_user" == true ]]; then
    if signed_in_oid="$(az ad signed-in-user show --query id -o tsv 2>/dev/null)" && [[ -n "$signed_in_oid" ]]; then
      demo_user_oids+=("$signed_in_oid")
    else
      echo "Warning: could not resolve signed-in user OID; demoUserPrincipalIds will only include explicit --demo-user-oid values." >&2
    fi
  fi

  # Deduplicate.
  if [[ ${#demo_user_oids[@]} -gt 0 ]]; then
    demo_user_json="$(printf '%s\n' "${demo_user_oids[@]}" | awk '!seen[$0]++' | jq -R . | jq -s -c .)"
  else
    demo_user_json='[]'
  fi

  if [[ "$what_if" == true ]]; then
    echo "Running what-if deployment preview..."
    az deployment sub what-if \
      --location "$location" \
      --template-file "infra/main.bicep" \
      --parameters "@${parameters_file}" \
      --parameters "demoUserPrincipalIds=${demo_user_json}"

    ok "What-if completed"
    echo "Note: remember to chmod +x scripts/*.sh (and later git update-index --chmod=+x for tracked shell scripts)."
    exit 0
  fi

  echo "Running subscription deployment ${deployment_name}..."
  echo "Demo user OIDs granted Key Vault Secrets User: ${demo_user_json}"
  deploy_json="$(az deployment sub create \
    --name "$deployment_name" \
    --location "$location" \
    --template-file "infra/main.bicep" \
    --parameters "@${parameters_file}" \
    --parameters "demoUserPrincipalIds=${demo_user_json}" \
    -o json)"

  mkdir -p .azure
  outputs_file=".azure/last-deploy-outputs.json"
  jq '.properties.outputs' <<<"$deploy_json" > "$outputs_file"

  enterprise_policy_arm_id="$(jq -r '.enterprisePolicyArmId.value' "$outputs_file")"
  key_vault_name="$(jq -r '.keyVaultName.value' "$outputs_file")"
  key_vault_uri="$(jq -r '.keyVaultUri.value' "$outputs_file")"
  sql_server_fqdn="$(jq -r '.sqlServerFqdn.value' "$outputs_file")"
  sql_database_name="$(jq -r '.sqlDatabaseName.value' "$outputs_file")"
  storage_account_name="$(jq -r '.storageAccountName.value' "$outputs_file")"
  uami_resource_id="$(jq -r '.userAssignedIdentityResourceId.value' "$outputs_file")"
  uami_principal_id="$(jq -r '.userAssignedIdentityPrincipalId.value' "$outputs_file")"

  ok "Deployment completed"
  echo
  echo "Deployment outputs"
  echo "------------------"
  echo "Enterprise policy ARM ID : ${enterprise_policy_arm_id}"
  echo "Key Vault                : ${key_vault_name}"
  echo "Key Vault URI            : ${key_vault_uri}"
  echo "SQL Server FQDN          : ${sql_server_fqdn}"
  echo "SQL Database             : ${sql_database_name}"
  echo "Storage account          : ${storage_account_name}"
  echo "UAMI resource ID         : ${uami_resource_id}"
  echo "UAMI principal ID        : ${uami_principal_id}"
  echo
  echo "Saved outputs to ${outputs_file}"
  echo "Next: Run ./scripts/02-configure-pp-vnet.ps1"
  echo "Note: remember to chmod +x scripts/*.sh (and later git update-index --chmod=+x for tracked shell scripts)."
}

main "$@"
