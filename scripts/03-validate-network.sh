#!/usr/bin/env bash
set -euo pipefail

# Purpose: Validate that the deployed services are locked down publicly and that Azure-side Private Link DNS wiring matches the expected private endpoint IPs.
# Usage: ./scripts/03-validate-network.sh
# Args: none

GREEN='\033[1;32m'
RED='\033[1;31m'
RESET='\033[0m'
OUTPUTS_FILE='.azure/last-deploy-outputs.json'
KV_ZONE='privatelink.vaultcore.azure.net'
SQL_ZONE='privatelink.database.windows.net'
BLOB_ZONE='privatelink.blob.core.windows.net'
DELEGATED_SUBNET_NAME='snet-pp-delegated'
DELEGATION_SERVICE='Microsoft.PowerPlatform/enterprisePolicies'
TEST_CONTAINER='demo'
TEST_BLOB='hello.txt'

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

assert_http_status() {
  local name="$1"
  local actual="$2"
  local expected="$3"

  if [[ "$actual" == "$expected" ]]; then
    ok "${name}: HTTP ${actual}"
    return 0
  fi

  fail "${name}: expected HTTP ${expected}, got ${actual:-000}"
  return 1
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

assert_non_empty() {
  local label="$1"
  local value="$2"

  if [[ -n "$value" ]]; then
    ok "${label}: ${value}"
    return 0
  fi

  fail "${label}: value was empty"
  return 1
}

lookup_resource_group() {
  local resource_id="$1"
  az resource show --ids "$resource_id" --query resourceGroup -o tsv | tr -d '\r'
}

lookup_resource_id() {
  local name="$1"
  local resource_type="$2"
  az resource list --name "$name" --resource-type "$resource_type" --query '[0].id' -o tsv | tr -d '\r'
}

lookup_private_endpoint_ip() {
  local resource_group="$1"
  local target_resource_id="$2"

  az network private-endpoint list \
    -g "$resource_group" \
    --query "[?privateLinkServiceConnections[0].properties.privateLinkServiceId=='${target_resource_id}'] | [0].customDnsConfigs[0].ipAddresses[0]" \
    -o tsv | tr -d '\r'
}

lookup_private_dns_ip() {
  local resource_group="$1"
  local zone_name="$2"
  local record_name="$3"

  az network private-dns record-set a show \
    -g "$resource_group" \
    -z "$zone_name" \
    -n "$record_name" \
    --query 'arecords[0].ipv4Address' \
    -o tsv | tr -d '\r'
}

probe_sql_public_denial() {
  local sql_fqdn="$1"
  local test_result=''
  # Pre-assign PS command to a variable: { } inside a double-quoted assignment is safe;
  # the brace-parse issue only occurs inside $(...) command substitutions.
  local ps_cmd="\$ProgressPreference='SilentlyContinue'; \$r = Test-NetConnection -ComputerName '${sql_fqdn}' -Port 1433 -WarningAction SilentlyContinue; if (\$r.TcpTestSucceeded) { 'True' } else { 'False' }"

  if command -v pwsh >/dev/null 2>&1; then
    test_result="$(pwsh -NoLogo -NoProfile -Command "$ps_cmd" | tr -d '\r')"
  elif command -v powershell.exe >/dev/null 2>&1; then
    test_result="$(powershell.exe -NoLogo -NoProfile -Command "$ps_cmd" | tr -d '\r')"
  elif command -v timeout >/dev/null 2>&1; then
    if timeout 5 bash -c "</dev/tcp/${sql_fqdn}/1433" >/dev/null 2>&1; then
      test_result='True'
    else
      test_result='False'
    fi
  else
    fail 'SQL public denial probe requires pwsh, powershell.exe, or timeout support'
    return 1
  fi

  if [[ "$test_result" == 'False' ]]; then
    ok 'SQL public endpoint is not reachable on TCP 1433 as expected'
    return 0
  fi

  fail 'SQL public endpoint unexpectedly accepted a TCP 1433 connection'
  return 1
}

assert_zone_links() {
  local resource_group="$1"
  local zone_name="$2"
  shift 2
  local expected_vnet_ids=("$@")
  local linked_vnet_ids

  linked_vnet_ids="$(az network private-dns link vnet list -g "$resource_group" -z "$zone_name" --query '[].virtualNetwork.id' -o tsv | tr -d '\r')"

  for expected_vnet_id in "${expected_vnet_ids[@]}"; do
    if grep -Fxq "$expected_vnet_id" <<<"$linked_vnet_ids"; then
      ok "${zone_name} linked to ${expected_vnet_id}"
    else
      fail "${zone_name} is missing a virtual network link to ${expected_vnet_id}"
      return 1
    fi
  done

  return 0
}

assert_private_dns_matches_endpoint() {
  local resource_group="$1"
  local zone_name="$2"
  local record_name="$3"
  local expected_ip="$4"
  local actual_ip

  actual_ip="$(lookup_private_dns_ip "$resource_group" "$zone_name" "$record_name")"
  assert_non_empty "${zone_name}/${record_name} private DNS A record" "$actual_ip" || return 1

  if [[ "$actual_ip" == "$expected_ip" ]]; then
    ok "${zone_name}/${record_name} resolves to private endpoint IP ${actual_ip}"
    return 0
  fi

  fail "${zone_name}/${record_name}: expected private endpoint IP ${expected_ip}, got ${actual_ip}"
  return 1
}

main() {
  local kv_name storage_name sql_fqdn sql_server_name sql_database_name
  local kv_id sql_id storage_id resource_group
  local storage_anon_code storage_sas_code
  local kv_pna sql_pna storage_pna storage_public_blob storage_sas account_key sas_expiry sas_token
  local kv_pe_ip sql_pe_ip storage_pe_ip
  local exit_code=0
  local delegated_vnet_ids_raw
  local -a delegated_vnet_ids=()

  require_command jq
  require_command az
  require_command curl

  if [[ ! -f "$OUTPUTS_FILE" ]]; then
    fail "Deployment outputs file not found: ${OUTPUTS_FILE}"
    exit 1
  fi

  kv_name="$(jq -r '.keyVaultName.value' "$OUTPUTS_FILE")"
  storage_name="$(jq -r '.storageAccountName.value' "$OUTPUTS_FILE")"
  sql_fqdn="$(jq -r '.sqlServerFqdn.value' "$OUTPUTS_FILE")"
  sql_database_name="$(jq -r '.sqlDatabaseName.value' "$OUTPUTS_FILE")"
  sql_server_name="${sql_fqdn%%.database.windows.net}"

  kv_id="$(az keyvault show -n "$kv_name" --query id -o tsv | tr -d '\r')"
  sql_id="$(lookup_resource_id "$sql_server_name" 'Microsoft.Sql/servers')"
  storage_id="$(lookup_resource_id "$storage_name" 'Microsoft.Storage/storageAccounts')"

  assert_non_empty 'Key Vault resource ID' "$kv_id" || exit_code=1
  assert_non_empty 'SQL Server resource ID' "$sql_id" || exit_code=1
  assert_non_empty 'Storage account resource ID' "$storage_id" || exit_code=1

  resource_group="$(lookup_resource_group "$sql_id")"
  assert_non_empty 'Resource group' "$resource_group" || exit_code=1

  echo 'Public-side negative-path checks (expected to fail)...'
  # Azure KV returns HTTP 401 (not 403) for unauthenticated requests even when publicNetworkAccess=Disabled
  # because the auth layer runs before the network ACL check on unauthenticated callers.
  # The correct deny-path proof requires an authenticated request, which then yields ForbiddenByConnection (403).
  local kv_deny_output
  kv_deny_output="$(az keyvault secret list --vault-name "$kv_name" 2>&1 || true)"
  if echo "$kv_deny_output" | grep -q 'ForbiddenByConnection'; then
    ok 'Key Vault public endpoint: ForbiddenByConnection (authenticated deny as expected)'
  else
    fail "Key Vault public endpoint did not return ForbiddenByConnection; got: ${kv_deny_output}"
    exit_code=1
  fi
  probe_sql_public_denial "$sql_fqdn" || exit_code=1
  storage_public_blob="https://${storage_name}.blob.core.windows.net/${TEST_CONTAINER}/${TEST_BLOB}"
  storage_anon_code="$(curl -sS -o /dev/null -w '%{http_code}\n' "$storage_public_blob" 2>/dev/null || true)"
  assert_http_status 'Storage public anonymous blob GET' "$storage_anon_code" '403' || exit_code=1

  account_key="$(az storage account keys list -g "$resource_group" -n "$storage_name" --query '[0].value' -o tsv 2>/dev/null | tr -d '\r' || true)"
  if [[ -z "$account_key" ]]; then
    fail 'Could not retrieve a storage account key; cannot validate SAS-over-public denial path'
    exit_code=1
  else
    if command -v pwsh >/dev/null 2>&1; then
      sas_expiry="$(pwsh -NoLogo -NoProfile -Command "(Get-Date).ToUniversalTime().AddMinutes(15).ToString('yyyy-MM-ddTHH:mmZ')" | tr -d '\r')"
    elif command -v powershell.exe >/dev/null 2>&1; then
      sas_expiry="$(powershell.exe -NoLogo -NoProfile -Command "(Get-Date).ToUniversalTime().AddMinutes(15).ToString('yyyy-MM-ddTHH:mmZ')" | tr -d '\r')"
    else
      sas_expiry="$(date -u -d '+15 minutes' +%Y-%m-%dT%H:%MZ 2>/dev/null || true)"
    fi

    if [[ -z "$sas_expiry" ]]; then
      fail 'Could not generate a SAS expiry timestamp'
      exit_code=1
    else
      sas_token="$(az storage blob generate-sas \
        --account-name "$storage_name" \
        --account-key "$account_key" \
        --container-name "$TEST_CONTAINER" \
        --name "$TEST_BLOB" \
        --permissions r \
        --expiry "$sas_expiry" \
        -o tsv | tr -d '\r')"

      if [[ -z "$sas_token" ]]; then
        fail 'Could not generate a SAS token for the storage denial probe'
        exit_code=1
      else
        storage_sas="${storage_public_blob}?${sas_token}"
        storage_sas_code="$(curl -sS -o /dev/null -w '%{http_code}\n' "$storage_sas" 2>/dev/null || true)"
        assert_http_status 'Storage public SAS blob GET' "$storage_sas_code" '403' || exit_code=1
      fi
    fi
  fi

  echo
  echo 'Azure-side Private Link DNS checks...'
  kv_pe_ip="$(lookup_private_endpoint_ip "$resource_group" "$kv_id")"
  sql_pe_ip="$(lookup_private_endpoint_ip "$resource_group" "$sql_id")"
  storage_pe_ip="$(lookup_private_endpoint_ip "$resource_group" "$storage_id")"

  assert_non_empty 'Key Vault private endpoint IP' "$kv_pe_ip" || exit_code=1
  assert_non_empty 'SQL private endpoint IP' "$sql_pe_ip" || exit_code=1
  assert_non_empty 'Storage private endpoint IP' "$storage_pe_ip" || exit_code=1

  assert_private_dns_matches_endpoint "$resource_group" "$KV_ZONE" "$kv_name" "$kv_pe_ip" || exit_code=1
  assert_private_dns_matches_endpoint "$resource_group" "$SQL_ZONE" "$sql_server_name" "$sql_pe_ip" || exit_code=1
  assert_private_dns_matches_endpoint "$resource_group" "$BLOB_ZONE" "$storage_name" "$storage_pe_ip" || exit_code=1

  delegated_vnet_ids_raw="$(az network vnet list -g "$resource_group" --query "[?subnets[?name=='${DELEGATED_SUBNET_NAME}' && delegations[?serviceName=='${DELEGATION_SERVICE}']]].id" -o tsv | tr -d '\r')"
  while IFS= read -r vnet_id; do
    [[ -n "$vnet_id" ]] && delegated_vnet_ids+=("$vnet_id")
  done <<<"$delegated_vnet_ids_raw"

  if [[ "${#delegated_vnet_ids[@]}" -lt 2 ]]; then
    fail "Expected at least two VNets with delegated subnet ${DELEGATED_SUBNET_NAME}, found ${#delegated_vnet_ids[@]}"
    exit_code=1
  else
    ok "Found ${#delegated_vnet_ids[@]} VNets with delegated subnet ${DELEGATED_SUBNET_NAME}"
    assert_zone_links "$resource_group" "$KV_ZONE" "${delegated_vnet_ids[@]}" || exit_code=1
    assert_zone_links "$resource_group" "$SQL_ZONE" "${delegated_vnet_ids[@]}" || exit_code=1
    assert_zone_links "$resource_group" "$BLOB_ZONE" "${delegated_vnet_ids[@]}" || exit_code=1
  fi

  echo
  echo 'Azure control-plane assertions...'
  kv_pna="$(az keyvault show -n "$kv_name" --query properties.publicNetworkAccess -o tsv | tr -d '\r')"
  sql_pna="$(az resource show --ids "$sql_id" --query properties.publicNetworkAccess -o tsv | tr -d '\r')"
  storage_pna="$(az storage account show -n "$storage_name" --query publicNetworkAccess -o tsv | tr -d '\r')"

  assert_equals 'Key Vault publicNetworkAccess' "$kv_pna" 'Disabled' || exit_code=1
  assert_equals 'SQL Server publicNetworkAccess' "$sql_pna" 'Disabled' || exit_code=1
  assert_equals 'Storage account publicNetworkAccess' "$storage_pna" 'Disabled' || exit_code=1

  echo
  echo 'Managed Environment runtime reminder:'
  echo '  This script validates Azure-side DNS wiring and operator-side public denial paths.'
  echo '  The allow-path proof from inside snet-pp-delegated must still come from a Managed Environment flow or custom connector test.'
  echo "  Run the connector tests in docs/connectors/ and the walkthrough in docs/demo-script.md for the inside-subnet proof."
  echo "  Expected allow-path result: <keyVaultName>.vault.azure.net, ${sql_fqdn}, and ${storage_name}.blob.core.windows.net resolve through Private Link from the Managed Environment runtime."

  echo
  if [[ "$exit_code" -eq 0 ]]; then
    ok 'All validation checks passed'
    exit 0
  fi

  fail 'One or more validation checks failed'
  exit 1
}

main "$@"
