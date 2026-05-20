#!/usr/bin/env bash
set -euo pipefail

# Purpose: Validate that the deployed services are locked down publicly and expose the expected Private Link DNS chain.
# Usage: ./scripts/03-validate-network.sh
# Args: none

GREEN='\033[1;32m'
RED='\033[1;31m'
RESET='\033[0m'
RG_NAME='rg-pbinet-dev'
OUTPUTS_FILE='.azure/last-deploy-outputs.json'

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

assert_non_2xx() {
  local name="$1"
  local code="$2"

  if [[ "$code" =~ ^2[0-9][0-9]$ ]]; then
    fail "${name} returned unexpected success status ${code}"
    return 1
  fi

  ok "${name} is not publicly reachable as expected (HTTP ${code:-000})"
  return 0
}

assert_equals() {
  local label="$1"
  local actual="$2"
  local expected="$3"

  if [[ "$actual" == "$expected" ]]; then
    ok "${label}: ${actual}"
    return 0
  fi

  fail "${label}: expected ${expected}, got ${actual}"
  return 1
}

main() {
  local kv_name storage_name sql_fqdn sql_server_name
  local kv_code sql_code storage_code
  local kv_dns sql_dns storage_dns
  local kv_pna sql_pna storage_pna
  local exit_code=0

  require_command jq
  require_command az
  require_command curl
  require_command dig

  if [[ ! -f "$OUTPUTS_FILE" ]]; then
    fail "Deployment outputs file not found: ${OUTPUTS_FILE}"
    exit 1
  fi

  kv_name="$(jq -r '.keyVaultName.value' "$OUTPUTS_FILE")"
  storage_name="$(jq -r '.storageAccountName.value' "$OUTPUTS_FILE")"
  sql_fqdn="$(jq -r '.sqlServerFqdn.value' "$OUTPUTS_FILE")"
  sql_server_name="${sql_fqdn%%.database.windows.net}"

  echo 'Public-side reachability checks (expected to fail)...'
  kv_code="$(curl -sS -o /dev/null -w '%{http_code}\n' "https://${kv_name}.vault.azure.net/secrets?api-version=7.4" 2>/dev/null || true)"
  sql_code="$(curl -sS -o /dev/null -w '%{http_code}\n' "https://${sql_fqdn}" 2>/dev/null || true)"
  storage_code="$(curl -sS -o /dev/null -w '%{http_code}\n' "https://${storage_name}.blob.core.windows.net" 2>/dev/null || true)"

  assert_non_2xx 'Key Vault public endpoint' "$kv_code" || exit_code=1
  assert_non_2xx 'SQL public endpoint' "$sql_code" || exit_code=1
  assert_non_2xx 'Storage public endpoint' "$storage_code" || exit_code=1

  echo
  echo 'DNS resolution checks...'
  # Outside the VNet, dig +short will usually show the privatelink CNAME chain and then a public placeholder IP.
  # Inside the VNet, the same names should resolve to the private endpoint IPs in the lab address space.
  kv_dns="$(dig +short "${kv_name}.vault.azure.net")"
  sql_dns="$(dig +short "$sql_fqdn")"
  storage_dns="$(dig +short "${storage_name}.blob.core.windows.net")"

  echo "Key Vault DNS:" && echo "$kv_dns"
  echo "SQL DNS:" && echo "$sql_dns"
  echo "Storage DNS:" && echo "$storage_dns"

  if grep -qi 'privatelink.vaultcore.azure.net' <<<"$kv_dns"; then
    ok 'Key Vault DNS shows privatelink chain'
  else
    fail 'Key Vault DNS did not show privatelink.vaultcore.azure.net'
    exit_code=1
  fi

  if grep -qi 'privatelink.database.windows.net' <<<"$sql_dns"; then
    ok 'SQL DNS shows privatelink chain'
  else
    fail 'SQL DNS did not show privatelink.database.windows.net'
    exit_code=1
  fi

  if grep -qi 'privatelink.blob.core.windows.net' <<<"$storage_dns"; then
    ok 'Storage DNS shows privatelink chain'
  else
    fail 'Storage DNS did not show privatelink.blob.core.windows.net'
    exit_code=1
  fi

  echo
  echo 'Inside-VNet check:'
  echo '  Run nslookup from a jump host, Cloud Shell with VNet integration, or the Power Automate flow during the demo.'
  echo "  nslookup ${kv_name}.vault.azure.net"
  echo "  nslookup ${sql_fqdn}"
  echo "  nslookup ${storage_name}.blob.core.windows.net"
  echo '  Expected result inside the VNet: private IPs such as 10.10.1.x instead of the public placeholder addresses shown outside.'

  echo
  echo 'Azure control-plane assertions...'
  kv_pna="$(az keyvault show -n "$kv_name" --query properties.publicNetworkAccess -o tsv)"
  sql_pna="$(az sql server show -n "$sql_server_name" -g "$RG_NAME" --query publicNetworkAccess -o tsv)"
  storage_pna="$(az storage account show -n "$storage_name" --query publicNetworkAccess -o tsv)"

  assert_equals 'Key Vault publicNetworkAccess' "$kv_pna" 'Disabled' || exit_code=1
  assert_equals 'SQL Server publicNetworkAccess' "$sql_pna" 'Disabled' || exit_code=1
  assert_equals 'Storage account publicNetworkAccess' "$storage_pna" 'Disabled' || exit_code=1

  echo
  if [[ "$exit_code" -eq 0 ]]; then
    ok 'All validation checks passed'
    echo 'Note: remember to chmod +x scripts/*.sh (and later git update-index --chmod=+x for tracked shell scripts).'
    exit 0
  fi

  fail 'One or more validation checks failed'
  exit 1
}

main "$@"
