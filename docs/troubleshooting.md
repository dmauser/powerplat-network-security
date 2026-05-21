# Troubleshooting Power Platform VNet connectivity

This guide provides runtime diagnostics for Power Platform VNet support using the `Microsoft.PowerPlatform.EnterprisePolicies` PowerShell module. It complements [monitoring.md](./monitoring.md) (passive log capture) with active troubleshooting (DNS, TCP, TLS validation). Use this when flows fail, connectivity breaks, or you need to confirm the private path is working end-to-end.

## Contents

- [Prerequisites and module setup](#prerequisites-and-module-setup)
- [Reference: diagnostic cmdlets](#reference-diagnostic-cmdlets)
- [Scenario 5.1: Different region works but another doesn't](#scenario-51-different-region-works-but-another-doesnt)
- [Scenario 5.2: Hostname not found](#scenario-52-hostname-not-found)
- [Scenario 5.3: Public IP returned instead of private](#scenario-53-public-ip-returned-instead-of-private)
- [Scenario 5.4: Can't connect to resource](#scenario-54-cant-connect-to-resource)
- [Scenario 5.5: TLS handshake fails](#scenario-55-tls-handshake-fails)
- [Scenario 5.6: Connectivity OK but app fails](#scenario-56-connectivity-ok-but-app-fails)
- [Worked example: Key Vault private path end-to-end](#worked-example-key-vault-private-path-end-to-end)
- [After diagnostics: finding root cause in logs](#after-diagnostics-finding-root-cause-in-logs)
- [When diagnostics aren't enough](#when-diagnostics-arent-enough)
- [Quick reference: old config issues](#quick-reference-old-config-issues)
- [Learn more](#learn-more)

---

## Prerequisites and module setup

All diagnostic commands require:

1. **PowerShell 7+** on your local workstation
2. **Azure CLI** (for pre-flight checks and role verification)
3. **Microsoft.PowerPlatform.EnterprisePolicies module** (install once, reuse)

### Install and import the module

```powershell
# Install (one-time)
Install-Module -Name Microsoft.PowerPlatform.EnterprisePolicies -Force

# Import into your session
Import-Module Microsoft.PowerPlatform.EnterprisePolicies
```

### Sign in to Power Platform

```powershell
# Authenticate to Power Platform (opens browser)
Add-PowerAppsAccount
```

You will need:
- A Power Platform admin account with access to the target environment
- Azure RBAC permissions to read the enterprise policy and run commands against the target VNets

### Collect your lab identifiers

From the output of `./scripts/01-deploy.sh` and your Power Platform admin center, gather:

```powershell
# Lab values (from deploy output)
$SubscriptionId = "43d55e51-58fe-486f-9e2a-ba56b8dd15de"
$ResourceGroup = "rg-pbinet-dev-eastus"
$EnvironmentId = "<your-managed-environment-guid>"

# Lab resources
$KeyVaultName = "kv-pbinet-dev-k6ozyjreme"
$KeyVaultFqdn = "kv-pbinet-dev-k6ozyjreme.vault.azure.net"
$SqlFqdn = "sql-pbinet-dev-k6ozyjremes6m.database.windows.net"
$StorageFqdn = "stpbinetdevk6ozyjremes6m.blob.core.windows.net"

# Azure regions
$RegionEast = "eastus"
$RegionWest = "westus"
```

---

## Reference: diagnostic cmdlets

| Cmdlet | What it tests | Lab example |
|--------|------|------|
| `Get-EnvironmentRegion` | Environment geography (must match VNet pair) | `Get-EnvironmentRegion -EnvironmentId $EnvironmentId` — should return "unitedstates" |
| `Get-EnvironmentUsage` | Power Platform capacity and resource usage | `Get-EnvironmentUsage -EnvironmentId $EnvironmentId` — verify delegated subnet is linked |
| `Test-DnsResolution` | Does hostname resolve to private IP? | `Test-DnsResolution -EnvironmentId $EnvironmentId -HostName $KeyVaultFqdn` — should return 10.10.x.x (not public) |
| `Test-NetworkConnectivity` | Can we reach the resource on the target port? | `Test-NetworkConnectivity -EnvironmentId $EnvironmentId -Destination $KeyVaultFqdn -Port 443` — confirms TCP connection |
| `Test-TLSHandshake` | Can we establish a TLS session? | `Test-TLSHandshake -EnvironmentId $EnvironmentId -Destination $KeyVaultFqdn -Port 443` — validates cert chain + handshake |

Reference: [Microsoft.PowerPlatform.EnterprisePolicies module](https://learn.microsoft.com/en-us/powershell/module/microsoft.powerplatform.enterprisepolicies/)

---

## Scenario 5.1: Different region works but another doesn't

**Symptom**  
One region (e.g., eastus) connectivity passes all tests, but the same test fails in westus, or flows work in one region but not the other.

**Root cause**  
Power Platform can failover between the two regions that pair a geography (eastus + westus for United States). If VNet support is only configured in one region, traffic from the other region will be blocked.

**Diagnosis**

```powershell
# Confirm the environment's current region
Get-EnvironmentRegion -EnvironmentId $EnvironmentId
# Expected output: "unitedstates" (the GEOGRAPHY, not the Azure region)

# Test DNS resolution from both Azure regions
Test-DnsResolution -EnvironmentId $EnvironmentId -HostName $KeyVaultFqdn -Region $RegionEast
# Expected: private IP (10.10.x.x)

Test-DnsResolution -EnvironmentId $EnvironmentId -HostName $KeyVaultFqdn -Region $RegionWest
# Expected: private IP (10.20.x.x) — if this returns public IP or fails, westus is not configured
```

**Fix**  
Verify that:
1. **Both VNets are deployed** — eastus (10.10.0.0/16) and westus (10.20.0.0/16) with global peering
2. **Both VNets are linked to the enterprise policy** — the policy must reference `snet-pp-delegated` subnets in BOTH regions
3. **Both private DNS zones are linked to BOTH VNets** — all 3 zones (vaultcore, database, blob) must link to east + west
4. **Subnet injection is complete** — re-run `Enable-SubnetInjection` or verify it includes both region references

See [architecture.md](./architecture.md) and [deployment-guide.md](./deployment-guide.md#step-3-configure-power-platform-vnet-support).

Reference: [Supported regions for Power Platform virtual network](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview#supported-regions)

---

## Scenario 5.2: Hostname not found

**Symptom**  
DNS resolution fails with "hostname not found" or times out. `Test-DnsResolution` returns an error instead of an IP.

**Root cause**  
The DNS server in the delegated subnet cannot resolve the hostname, either because:
- The private DNS zone doesn't exist
- The zone is not linked to the VNet
- The private endpoint doesn't have a corresponding DNS record

**Diagnosis**

```powershell
# Test DNS resolution (this initiates from the delegated subnet)
Test-DnsResolution -EnvironmentId $EnvironmentId -HostName $KeyVaultFqdn
# If this fails: "Unable to resolve hostname" or similar, DNS is misconfigured

# Cross-check: does the private DNS zone exist in Azure?
az network private-dns zone show \
  --resource-group $ResourceGroup \
  --name "privatelink.vaultcore.azure.net" \
  --query id
# If this returns nothing, the zone was not created during deployment
```

**Fix**  
1. Verify the private DNS zone exists: `privatelink.vaultcore.azure.net`, `privatelink.database.windows.net`, `privatelink.blob.core.windows.net`
2. Verify the zone is linked to **both** VNets (eastus + westus)
3. Verify the DNS A record exists and maps to the private endpoint IP:

```bash
az network private-dns record-set a show \
  --resource-group $ResourceGroup \
  --zone-name "privatelink.vaultcore.azure.net" \
  --name $KeyVaultName \
  --query "aRecords[0].ipv4Address"
# Expected: 10.10.1.4 (or similar private endpoint IP in snet-pep)
```

4. If records are missing, re-run the private endpoint creation or validate the integration:

```bash
./scripts/03-validate-network.sh
```

Reference: [Troubleshoot hostname not found — Power Platform](https://learn.microsoft.com/en-us/troubleshoot/power-platform/administration/virtual-network#hostname-not-found)

---

## Scenario 5.3: Public IP returned instead of private

**Symptom**  
`Test-DnsResolution` returns a public IP (e.g., `52.x.x.x` or similar) instead of a private endpoint IP (10.x.x.x). The flow runs but you suspect it's hitting the public endpoint instead of the private one.

**Root cause**  
The private DNS zone is not linked to the VNet where the request originates, so the request falls back to public DNS and resolves to the public endpoint. This is the most common issue in multi-region setups where one VNet is missing the zone link.

**Diagnosis**

```powershell
# Test DNS resolution
Test-DnsResolution -EnvironmentId $EnvironmentId -HostName $KeyVaultFqdn
# If output is a public IP, the zone is not linked to the VNet

# Verify the private DNS zone is linked to BOTH VNets
az network private-dns link vnet list \
  --resource-group $ResourceGroup \
  --zone-name "privatelink.vaultcore.azure.net" \
  --query "[].virtualNetwork.id"
# Expected: 2 VNet IDs (eastus and westus)
```

**Fix**  
1. Link the private DNS zone to both VNets:

```bash
# Link to eastus VNet
az network private-dns link vnet create \
  --resource-group $ResourceGroup \
  --zone-name "privatelink.vaultcore.azure.net" \
  --name "vnet-link-east" \
  --virtual-network "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Network/virtualNetworks/vnet-east"

# Link to westus VNet
az network private-dns link vnet create \
  --resource-group $ResourceGroup \
  --zone-name "privatelink.vaultcore.azure.net" \
  --name "vnet-link-west" \
  --virtual-network "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Network/virtualNetworks/vnet-west"
```

2. Repeat for the other two zones: `privatelink.database.windows.net` and `privatelink.blob.core.windows.net`

3. Wait 1–2 minutes for DNS to propagate, then re-test:

```powershell
Test-DnsResolution -EnvironmentId $EnvironmentId -HostName $KeyVaultFqdn
# Should now return 10.10.x.x (private)
```

Reference: [Request uses a public IP address instead of the private IP address — Power Platform](https://learn.microsoft.com/en-us/troubleshoot/power-platform/administration/virtual-network#request-uses-a-public-ip-address-instead-of-the-private-ip-address)

---

## Scenario 5.4: Can't connect to resource

**Symptom**  
DNS resolution succeeds (returns private IP), but `Test-NetworkConnectivity` fails or times out. The flow returns a connection timeout or "unable to reach host."

**Root cause**  
Network layer issue:
- NSG rules block the port (443 for HTTPS, 1433 for SQL, etc.)
- Network route is missing or incorrect
- Private endpoint is not accepting traffic
- Firewall rule on the resource (Key Vault, SQL, Storage) denies the delegated subnet

**Diagnosis**

```powershell
# Test TCP connectivity to Key Vault (443 = HTTPS)
Test-NetworkConnectivity -EnvironmentId $EnvironmentId -Destination $KeyVaultFqdn -Port 443
# Expected: success

# Test SQL Server (1433 = SQL Server)
Test-NetworkConnectivity -EnvironmentId $EnvironmentId -Destination $SqlFqdn -Port 1433
# Expected: success

# Test Blob Storage (443 = HTTPS)
Test-NetworkConnectivity -EnvironmentId $EnvironmentId -Destination $StorageFqdn -Port 443
# Expected: success
```

**Fix**  
1. Check NSG rules on `snet-pp-delegated`:

```bash
az network nsg rule list \
  --resource-group $ResourceGroup \
  --nsg-name "nsg-delegated" \
  --query "[].{priority:priority, direction:direction, access:access, sourceAddressPrefix:sourceAddressPrefix, destinationPortRange:destinationPortRange}"
# Should allow outbound HTTPS (443) and SQL (1433)
```

2. Check the private endpoint's network interface:

```bash
az network nic list \
  --resource-group $ResourceGroup \
  --query "[?contains(name, 'pep')].id"
# Verify the PE NICs exist in snet-pep
```

3. Verify the resource's firewall is not explicitly blocking the delegated subnet:

```bash
# For Key Vault
az keyvault show \
  --resource-group $ResourceGroup \
  --name $KeyVaultName \
  --query "properties.networkAcls"
# If virtualNetworkRules exist, verify they include the delegated subnets

# For SQL Server
az sql server firewall-rule list \
  --resource-group $ResourceGroup \
  --server $SqlServer \
  --query "[].{startIpAddress:startIpAddress, endIpAddress:endIpAddress}"
# Check that "Allow Azure services and resources to access this server" is ON
```

4. If the issue persists, check VNet flow logs to see where traffic is being dropped (NSP, NSG, or resource firewall):

See [monitoring.md](./monitoring.md#starter-kql-queries) for flow log analysis queries.

Reference: [Can't connect to the resource — Power Platform](https://learn.microsoft.com/en-us/troubleshoot/power-platform/administration/virtual-network#cant-connect-to-the-resource)

---

## Scenario 5.5: TLS handshake fails

**Symptom**  
`Test-NetworkConnectivity` succeeds (TCP port 443 is open), but `Test-TLSHandshake` fails. You see TLS alert codes like 40, 42, 48, 51, 112, or 116. Flow returns HTTPS/SSL errors.

**Root cause**  
Network layer is reachable, but TLS negotiation fails due to:
- Certificate validation issue (self-signed, expired, wrong hostname)
- TLS version mismatch
- Firewall or proxy intercepting HTTPS (unlikely in lab with private endpoints)
- Delegated subnet cannot reach the CRL/OCSP revocation server

**Diagnosis**

```powershell
# Test TLS handshake for Key Vault
Test-TLSHandshake -EnvironmentId $EnvironmentId -Destination $KeyVaultFqdn -Port 443
# If this fails, check the error details

# Test for SQL Server
Test-TLSHandshake -EnvironmentId $EnvironmentId -Destination $SqlFqdn -Port 1433
# SQL Server requires TLS; verify certificate
```

**Fix**  
1. Verify the resource's certificate is valid:

```bash
# For Key Vault
openssl s_client -connect "$KeyVaultFqdn:443" -servername "$KeyVaultFqdn" -showcerts 2>/dev/null | openssl x509 -noout -subject -dates
# Check Subject CN and validity dates

# For SQL Server
openssl s_client -connect "$SqlFqdn:1433" -starttls smtp -servername "$SqlFqdn" 2>&1 | openssl x509 -noout -subject
```

2. Verify the delegated subnet can reach certificate revocation servers. This is typically handled by the resource's firewall rules, which this lab configures correctly by default.

3. If using a custom DNS server in the VNet, verify it can resolve the certificate authority's domains (e.g., `ocsp.digicert.com`, `crl.digicert.com`).

4. Check the resource's TLS settings:

```bash
# For Azure SQL: minimum TLS version should be 1.2 or later
az sql server show \
  --resource-group $ResourceGroup \
  --name $SqlServer \
  --query "minimalTlsVersion"
```

Reference: [Can't establish a TLS handshake — Power Platform](https://learn.microsoft.com/en-us/troubleshoot/power-platform/administration/virtual-network#cant-establish-a-tls-handshake)

---

## Scenario 5.6: Connectivity OK but app fails

**Symptom**  
All diagnostic tests pass (DNS, TCP, TLS), but the Power Automate connector action still returns `403 Forbidden` or `401 Unauthorized`. The flow can reach the resource but cannot access it.

**Root cause**  
This is an authentication or authorization issue, not a network issue:
- RBAC role is missing or hasn't propagated
- Service principal or managed identity lacks permission
- Secret/credential is wrong or expired
- Resource requires additional configuration (e.g., contained user in SQL, CORS in Blob)

**Diagnosis**

```powershell
# Network path is working, so verify RBAC
# For Key Vault: the identity needs "Key Vault Secrets User" role
az role assignment list \
  --scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.KeyVault/vaults/$KeyVaultName" \
  --query "[].{principalName:principalName, roleDefinitionName:roleDefinitionName}"
# Should show the UAMI or service principal with "Key Vault Secrets User"

# For SQL Server: verify the SQL user/AAD principal is created
# (requires direct SQL access; covered in connectors/sql.md)

# For Blob Storage: the identity needs "Storage Blob Data Reader"
az role assignment list \
  --scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Storage/storageAccounts/$StorageAccount" \
  --query "[].{principalName:principalName, roleDefinitionName:roleDefinitionName}"
# Should show the UAMI with a data-plane role (not just "Storage Account Contributor")
```

**Fix**  
1. Grant the required RBAC roles:

```bash
# Get the UAMI principal ID
UAMI_ID="<from deploy output>"

# Key Vault Secrets User
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee $UAMI_ID \
  --scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.KeyVault/vaults/$KeyVaultName"

# Storage Blob Data Reader
az role assignment create \
  --role "Storage Blob Data Reader" \
  --assignee $UAMI_ID \
  --scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Storage/storageAccounts/$StorageAccount"
```

2. For SQL Server, create the AAD-backed database user (see [connectors/sql.md](./connectors/sql.md)).

3. Wait 1–2 minutes for RBAC propagation and retry the flow.

See also [security-notes.md](./security-notes.md) for the full RBAC and authentication guidance.

---

## Worked example: Key Vault private path end-to-end

This example walks through all five diagnostic tests for the lab's Key Vault setup, step by step.

**Goal:** Confirm the Managed Environment can reach `kv-pbinet-dev-k6ozyjreme.vault.azure.net` (private endpoint only, public access disabled) using only the private path.

### Step 1: Set up variables

```powershell
$EnvironmentId = "12345678-1234-1234-1234-123456789012"  # Your ME GUID
$KeyVaultName = "kv-pbinet-dev-k6ozyjreme"
$KeyVaultFqdn = "kv-pbinet-dev-k6ozyjreme.vault.azure.net"
$Region = "eastus"  # Primary region for this lab

# Sign in once
Import-Module Microsoft.PowerPlatform.EnterprisePolicies
Add-PowerAppsAccount
```

### Step 2: Verify geography

```powershell
$env = Get-EnvironmentRegion -EnvironmentId $EnvironmentId
Write-Host "Environment geography: $env"
# Output should be "unitedstates"
# If it's anything else, the VNet pair doesn't match and you must recreate the ME
```

### Step 3: Test DNS resolution

```powershell
$dnsResult = Test-DnsResolution -EnvironmentId $EnvironmentId -HostName $KeyVaultFqdn
Write-Host "DNS resolution: $dnsResult"
# Output should be 10.10.1.4 or similar (private endpoint IP in snet-pep)
# If it's 52.x.x.x or public, the private DNS zone is not linked to the VNet
```

### Step 4: Test TCP connectivity

```powershell
$tcpResult = Test-NetworkConnectivity -EnvironmentId $EnvironmentId -Destination $KeyVaultFqdn -Port 443
Write-Host "TCP connectivity to port 443: $tcpResult"
# Output should be "Success" or similar
# If it fails, NSG or resource firewall is blocking the delegated subnet
```

### Step 5: Test TLS handshake

```powershell
$tlsResult = Test-TLSHandshake -EnvironmentId $EnvironmentId -Destination $KeyVaultFqdn -Port 443
Write-Host "TLS handshake: $tlsResult"
# Output should be "Success" or similar
# If it fails, there's a certificate validation issue (unlikely with Azure-managed certs)
```

### Step 6: Verify RBAC in Azure portal or CLI

```bash
# From your local workstation
UAMI_ID="<from deploy output>"
az role assignment list \
  --scope "/subscriptions/43d55e51-58fe-486f-9e2a-ba56b8dd15de/resourceGroups/rg-pbinet-dev-eastus/providers/Microsoft.KeyVault/vaults/kv-pbinet-dev-k6ozyjreme" \
  --query "[].roleDefinitionName"
# Should list "Key Vault Secrets User" among others
```

### Step 7: Build and run a flow

Use the [keyvault.md](./connectors/keyvault.md) walkthrough to create a Power Automate flow that reads `demo-secret` from the vault. If all five tests above pass, the flow should succeed with a `200` response and the secret value in the output.

### Step 8: Verify public access is still blocked

From your local machine (not inside Power Platform), confirm the vault is still private:

```bash
curl -sS -o /dev/null -w "%{http_code}\n" \
  "https://kv-pbinet-dev-k6ozyjreme.vault.azure.net/secrets/demo-secret?api-version=7.4"
# Expected: 403 Forbidden
# This confirms the vault is not accessible from the public endpoint
```

**Outcome:**  
- Diagnostic tests 1–5: All pass ✅
- Flow execution: `200` with secret value ✅
- Public probe: `403` Forbidden ✅

This confirms the full private path is working end-to-end: delegated subnet → private DNS → private endpoint → vault (private access only).

---

## After diagnostics: finding root cause in logs

Once diagnostics confirm *which* layer has the problem (DNS, TCP, TLS, or auth), use [monitoring.md](./monitoring.md) to find the source in passive logs.

### If DNS failed

See [monitoring.md: DNS validation queries](./monitoring.md#starter-kql-queries) — use the `Test-DnsResolution` KQL query to audit all DNS lookups in the delegated subnet.

### If TCP connectivity failed

See [monitoring.md: flow log queries](./monitoring.md#starter-kql-queries) — use VNet flow logs to see:
- Which NSG rule denied the traffic
- Whether the traffic reached the private endpoint
- If the traffic was east-to-west (cross-VNet)

### If TLS failed

See [monitoring.md: TLS handshake debugging](./monitoring.md#troubleshooting-decision-tree) — check Application Insights or resource diagnostic logs for TLS alert codes and certificate validation errors.

### If auth failed (403 / 401)

See [monitoring.md: access audit queries](./monitoring.md#starter-kql-queries) — query NSP access logs to confirm the request arrived (private endpoint inbound), then check Key Vault audit logs or SQL login events for authentication failures.

---

## When diagnostics aren't enough

If all five tests pass but the flow still fails, or if you need deeper visibility into packet-level behavior:

### Option 1: Deploy a non-delegated VM for manual testing

Create a test VM in `snet-pep` (not delegated) and manually run `curl`, `psql`, or `sqlcmd` commands against the resources. This isolates whether the issue is specific to Power Platform or a general network problem.

```bash
# From inside the PE subnet, test Key Vault
curl -sS -H "Authorization: Bearer $(az account get-access-token --query accessToken -o tsv)" \
  "https://kv-pbinet-dev-k6ozyjreme.vault.azure.net/secrets/demo-secret?api-version=7.4"
# If this succeeds from the VM but Power Platform fails, the issue is PP-specific
```

### Option 2: Enable Network Security Perimeter Learning mode logs

NSP logs capture **all** inbound traffic attempts to the resources, including those that succeed and those denied by resource firewalls.

See [monitoring.md: Network Security Perimeter in Learning mode](./monitoring.md#network-security-perimeter-in-learning-mode) — query `NSPAccessLogs` to see if Power Platform requests are arriving at the private endpoint and what the resource firewall is doing.

```kusto
NSPAccessLogs
| where TimeGenerated > ago(15m)
| where ResourceName == "kv-pbinet-dev-k6ozyjreme"
| where Category == "NspPrivateInboundAllowed" or Category == "NspPublicInboundResourceRulesDenied"
| project TimeGenerated, Category, SourceIpAddress, DestinationIpAddress, DestinationPort, Action
| limit 50
```

### Option 3: Packet capture on the private endpoint

If you need TCP/TLS visibility, use Azure Network Watcher to capture traffic on the private endpoint's network interface:

```bash
az network watcher packet-capture create \
  --resource-group $ResourceGroup \
  --name "pe-capture" \
  --target "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Network/networkInterfaces/pep-kv-nic" \
  --storage-account $StorageAccountForCaptures
```

Download and analyze with Wireshark to see the exact TLS handshake, certificate exchanges, and any error codes.

See [monitoring.md: Packet capture mechanics](./monitoring.md#packet-capture-mechanics) for full guidance.

---

## Quick reference: old config issues

These are common misconfigurations found during troubleshooting of similar labs:

### Issue: "Enable-SubnetInjection fails with policy not found"

**Cause:**  
The enterprise policy ARM ID is wrong, or the policy wasn't deployed.

**Fix:**

```powershell
# Verify the policy exists
$policyId = Get-AzResource -ResourceGroupName $ResourceGroup -ResourceType "Microsoft.PowerPlatform/enterprisePolicies" -Name "ep-pbinet-dev"
Write-Host $policyId.ResourceId

# Re-run with the correct ID
Enable-SubnetInjection -EnvironmentId $EnvironmentId -EnterprisePolicy $policyId.ResourceId
```

### Issue: "Delegated subnet too small"

**Cause:**  
`snet-pp-delegated` was sized at `/27` (32 IPs) but the environment needs more IPs at runtime.

**Fix:**  
For a production workload, plan subnet size using the [Power Platform subnet sizing guidance](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview#estimating-subnet-size-for-power-platform-environments). For this lab, `/27` is sufficient for 1–2 environments. To expand, you must rebuild the VNet.

### Issue: "SQL ServerName resolved to public IP"

**Cause:**  
The private DNS zone `privatelink.database.windows.net` was not linked to the westus VNet.

**Fix:**  
Link the zone to both VNets and wait 1–2 minutes:

```bash
az network private-dns link vnet create \
  --resource-group $ResourceGroup \
  --zone-name "privatelink.database.windows.net" \
  --name "database-link-west" \
  --virtual-network "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Network/virtualNetworks/vnet-west"
```

---

## Learn more

- [Troubleshoot virtual network issues — Power Platform](https://learn.microsoft.com/en-us/troubleshoot/power-platform/administration/virtual-network)
- [Microsoft.PowerPlatform.EnterprisePolicies PowerShell module](https://learn.microsoft.com/en-us/powershell/module/microsoft.powerplatform.enterprisepolicies/)
- [PowerPlatform-EnterprisePolicies GitHub repository](https://github.com/microsoft/PowerPlatform-EnterprisePolicies)
- [Virtual Network support overview — Power Platform](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview)
- [Network observability and monitoring — this lab](./monitoring.md)
- [Lab architecture — this lab](./architecture.md)
