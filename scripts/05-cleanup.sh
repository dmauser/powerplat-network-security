#!/usr/bin/env bash
set -euo pipefail

# Purpose: Delete the demo resource group and optionally purge the soft-deleted Key Vault.
# Usage: ./scripts/05-cleanup.sh [--rg <name>] [--purge-kv] [--yes]
# Args:
#   --rg <name>   Resource group to delete. Default: rg-pbinet-dev
#   --purge-kv    After RG deletion completes, purge the Key Vault from the latest deployment outputs.
#   --yes         Skip the confirmation prompt.

GREEN='\033[1;32m'
RED='\033[1;31m'
RESET='\033[0m'
OUTPUTS_FILE='.azure/last-deploy-outputs.json'

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
  local rg_name='rg-pbinet-dev'
  local purge_kv=false
  local yes=false
  local kv_name=''
  local confirm=''

  if ! command -v az >/dev/null 2>&1; then
    fail 'Azure CLI (az) is required.'
    exit 1
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --rg)
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
    if ! command -v jq >/dev/null 2>&1; then
      fail 'jq is required when using --purge-kv.'
      exit 1
    fi

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

  # The enterprise policy resource lives inside the resource group, so the RG delete removes it automatically.
  az group delete -n "$rg_name" --yes --no-wait >/dev/null
  ok "Requested deletion of resource group ${rg_name}"

  if [[ "$purge_kv" == true ]]; then
    echo "Waiting for resource group ${rg_name} deletion to complete before purging Key Vault ${kv_name}..."
    while [[ "$(az group exists -n "$rg_name" -o tsv)" == 'true' ]]; do
      sleep 15
    done

    az keyvault purge -n "$kv_name" >/dev/null
    ok "Purged Key Vault ${kv_name}"
  fi

  echo
  echo 'Cleanup summary'
  echo '---------------'
  echo "Resource group delete requested: ${rg_name}"
  if [[ "$purge_kv" == true ]]; then
    echo "Key Vault purged:             ${kv_name}"
  else
    echo 'Key Vault purge:              skipped'
  fi
  echo 'Enterprise policy cleanup:    covered by resource group deletion'
  echo 'Note: remember to chmod +x scripts/*.sh (and later git update-index --chmod=+x for tracked shell scripts).'
}

main "$@"
