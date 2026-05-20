#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose: Delete the demo resource group and optionally purge the soft-deleted Key Vault.
# Usage: ./scripts/05-cleanup.sh [--rg <name>] [--purge-kv] [--yes]
# Args:
#   --rg <name>   Resource group to delete. Default: rg-pbinet-dev (or $PPNS_RESOURCE_GROUP)
#   --purge-kv    After RG deletion completes, purge the Key Vault from the latest deployment outputs.
#   --yes         Skip the confirmation prompt.

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
RESET='\033[0m'
OUTPUTS_FILE='.azure/last-deploy-outputs.json'

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

usage() {
  sed -n '4,9p' "$0"
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    fail "Missing required tool: ${command_name}"
    exit 1
  fi
}

main() {
  local rg_name="${PPNS_RESOURCE_GROUP:-rg-pbinet-dev}"
  local purge_kv=false
  local yes=false
  local kv_name=''
  local confirm=''
  local rg_exists='false'
  local deleted_vault_name=''

  require_command az

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --rg)
        if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
          fail 'The --rg option requires a resource group name.'
          usage
          exit 1
        fi
        rg_name="$2"
        shift 2
        ;;
      --purge-kv)
        purge_kv=true
        shift
        ;;
      --yes)
        yes=true
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

  if [[ "$purge_kv" == true ]]; then
    require_command jq

    if [[ ! -f "$OUTPUTS_FILE" ]]; then
      fail "Cannot purge Key Vault because ${OUTPUTS_FILE} was not found."
      exit 1
    fi

    kv_name="$(jq -r '.keyVaultName.value' "$OUTPUTS_FILE")"
    if [[ -z "$kv_name" || "$kv_name" == 'null' ]]; then
      fail 'Could not resolve Key Vault name from deployment outputs.'
      exit 1
    fi
  fi

  if [[ "$yes" != true ]]; then
    read -r -p "Delete resource group '${rg_name}'? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      fail 'Cleanup cancelled.'
      exit 1
    fi
  fi

  rg_exists="$(az group exists -n "$rg_name" -o tsv)"
  if [[ "$rg_exists" == 'true' ]]; then
    # The enterprise policy resource lives inside the resource group, so the RG delete removes it automatically.
    az group delete -n "$rg_name" --yes --no-wait >/dev/null
    ok "Requested deletion of resource group ${rg_name}"
  else
    warn "Resource group ${rg_name} does not exist. Skipping delete request."
  fi

  if [[ "$purge_kv" == true ]]; then
    if [[ "$rg_exists" == 'true' ]]; then
      echo "Waiting for resource group ${rg_name} deletion to complete before purging Key Vault ${kv_name}..."
      while [[ "$(az group exists -n "$rg_name" -o tsv)" == 'true' ]]; do
        sleep 15
      done
    fi

    deleted_vault_name="$(az keyvault list-deleted --query "[?name=='${kv_name}'].name | [0]" -o tsv 2>/dev/null || true)"
    if [[ "$deleted_vault_name" == "$kv_name" ]]; then
      az keyvault purge -n "$kv_name" >/dev/null
      ok "Purged Key Vault ${kv_name}"
    else
      warn "Key Vault ${kv_name} is not in the deleted state. Skipping purge."
    fi
  fi

  echo
  echo 'Cleanup summary'
  echo '---------------'
  if [[ "$rg_exists" == 'true' ]]; then
    echo "Resource group delete requested: ${rg_name}"
  else
    echo "Resource group delete requested: skipped (${rg_name} not found)"
  fi
  if [[ "$purge_kv" == true ]]; then
    if [[ "$deleted_vault_name" == "$kv_name" ]]; then
      echo "Key Vault purged:             ${kv_name}"
    else
      echo "Key Vault purged:             skipped (${kv_name} not deleted)"
    fi
  else
    echo 'Key Vault purge:              skipped'
  fi
  echo 'Enterprise policy cleanup:    covered by resource group deletion'
}

main "$@"
