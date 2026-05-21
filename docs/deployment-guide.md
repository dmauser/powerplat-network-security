# Deployment guide

This guide walks through the full lab sequence from prerequisites to connector validation. It assumes the Azure resources are deployed by `./scripts/01-deploy.sh`, the Power Platform environment is already a Managed Environment in the United States geography, and the maker will finish the demo by building flows that use private connectivity from the linked environment.

## Contents

- [Overview](#overview)
- [Step 1: prerequisites](#step-1-prerequisites)
- [Step 2: deploy Azure resources](#step-2-deploy-azure-resources)
- [Step 3: configure Power Platform VNet support](#step-3-configure-power-platform-vnet-support)
- [Step 4: validate network behavior](#step-4-validate-network-behavior)
- [Step 5: build connector flows](#step-5-build-connector-flows)
- [Operational notes](#operational-notes)

## Overview

The deployment flow follows the same split described in [architecture.md](./architecture.md): Azure infrastructure first, then Power Platform policy linkage, then maker-owned connector validation. Use [managed-environment-setup.md](./managed-environment-setup.md) before you start so the target environment is already managed and you have the correct environment ID.

## Step 1: prerequisites

Start with the environment preparation described in [managed-environment-setup.md](./managed-environment-setup.md), then run the prerequisites script.

```bash
./scripts/00-prereqs.sh
```

What this step should cover:

- Azure CLI or other required tooling is available.
- The subscription has `Microsoft.Network` and `Microsoft.PowerPlatform` resource providers registered.
- The `enterprisePoliciesPreview` feature is registered where needed, matching the [setup guidance](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-setup-configure).
- Required PowerShell modules are available for later steps.

### Validation checkpoints

After `00-prereqs.sh`:

- Resource providers are registered successfully.
- Preview feature registration completes or is already registered.
- No missing tooling errors remain.
- You know the target environment ID from [managed-environment-setup.md](./managed-environment-setup.md).

If this step fails, see [troubleshooting.md](./troubleshooting.md#enterprisepoliciespreview-not-registered-run-00-prereqssh).

## Step 2: deploy Azure resources

Run the infrastructure deployment.

```bash
./scripts/01-deploy.sh
```

Expected deployment shape:

- Two VNets: one in **eastus**, one in **westus**.
- In each VNet: `snet-pp-delegated /27` and `snet-pep /27`.
- Global VNet peering in both directions.
- Three private DNS zones linked to both VNets.
- Three private endpoints in the eastus `snet-pep` subnet.
- Key Vault, Azure SQL Database, and Storage account with `publicNetworkAccess=Disabled`.
- One user-assigned managed identity with principal ID emitted in outputs.
- One enterprise policy with `kind=NetworkInjection` referencing both delegated subnets.

Expected outputs to capture:

- `<enterprisePolicyArmId>`
- `<keyVaultName>`
- `<keyVaultUri>`
- `<sqlServerFqdn>`
- `<sqlDatabaseName>`
- `<storageAccountName>`
- `<userAssignedIdentityPrincipalId>`

### Validation checkpoints

After `01-deploy.sh`:

- The deploy output contains all seven values above.
- Key Vault, SQL, and Storage private endpoints are in the eastus `snet-pep` subnet.
- The three private DNS zones exist and are linked to both VNets.
- The enterprise policy ARM ID is ready for the next step.

If DNS or private endpoint validation fails, review [architecture.md](./architecture.md#private-dns) and [troubleshooting.md](./troubleshooting.md#dns-resolves-to-a-public-ip-from-inside-azure).

## Step 3: configure Power Platform VNet support

Link the Managed Environment to the enterprise policy.

```powershell
./scripts/02-configure-pp-vnet.ps1 -EnvironmentId <environmentId>
```

What this step should do:

- Auto-install or import the pinned [Microsoft.PowerPlatform.EnterprisePolicies module](https://learn.microsoft.com/en-us/powershell/module/microsoft.powerplatform.enterprisepolicies/) version 0.17.0 if needed.
- Confirm the environment region with `Get-EnvironmentRegion`.
- Use `Enable-SubnetInjection` to link the environment to `<enterprisePolicyArmId>`.
- If the same policy is already linked, exit cleanly with no changes applied (the script is safe to re-run).

### Validation checkpoints

After `02-configure-pp-vnet.ps1`:

- The environment is confirmed as a **United States** environment.
- `Enable-SubnetInjection` completes successfully.
- The policy ARM ID shown in output matches the deployment output.
- The environment is now ready to run private connector traffic.

If this step fails with a policy error or region mismatch, see [troubleshooting.md](./troubleshooting.md#get-environmentregion-returns-wrong-region) and [troubleshooting.md](./troubleshooting.md#enable-subnetinjection-fails-with-policy-not-found).

## Step 4: validate network behavior

Run the validation script after the environment is linked.

```bash
./scripts/03-validate-network.sh
```

Expected green checks or equivalent assertions:

- Environment region matches the deployment geography.
- DNS for Key Vault, SQL, and Blob resolves to private IPs.
- Key Vault, SQL, and Storage public network access is disabled.
- The enterprise policy references both delegated subnets.
- The linked environment can resolve and reach the target FQDNs through the delegated path.

### Validation checkpoints

After `03-validate-network.sh`:

- All DNS tests return private IP addresses.
- The enterprise policy reports both delegated subnets.
- No public endpoint path is required for the demo services.
- The lab is ready for maker validation.

If SQL connectivity is slow on first use, note the expected [serverless cold start behavior](./troubleshooting.md#sql-serverless-first-call-cold-start-30s-wake).

After validation passes, proceed to [monitoring.md](./monitoring.md) to confirm observability is in place.

### Network observability verification

Before running connector flows, confirm that Network Security Perimeter and VNet flow logs are active:

**NSP verification:**

```powershell
$nspName = "nsp-<prefix>-<env>"
$rg = "rg-<prefix>-<env>"
Get-AzResource -Name $nspName -ResourceGroupName $rg -ResourceType "Microsoft.Network/networkSecurityPerimeters"
```

Expected: NSP resource is found with all three resource associations (`assoc-kv`, `assoc-sql`, `assoc-storage`) in Learning mode.

**VNet flow logs verification:**

```powershell
Get-AzNetworkWatcherFlowLog -NetworkWatcherName "NetworkWatcher_eastus" -ResourceGroupName "NetworkWatcherRG" -Name "fl-vnet-<prefix>-<env>-east"
```

Expected: Flow log is enabled with `flowAnalyticsConfiguration.enabled = true`.

**Log Analytics readiness:**

Log into the Azure portal, open the Log Analytics workspace, and run this query:

```kql
NSPAccessLogs | where TimeGenerated > ago(1h) | count
```

Note: NSP logs and Traffic Analytics summaries appear with **5–15 minute latency**. If the tables are empty after initial deployment, this is normal—wait 15 minutes, run a test flow from the Managed Environment (see Step 5 below), then query again. See [monitoring.md](./monitoring.md#verification-steps) for detailed troubleshooting.

## Step 5: build connector flows

Use the deployment outputs to create and test flows from inside the Managed Environment.

Follow these connector walkthroughs:

- [Azure Key Vault connector demo](./connectors/keyvault.md)
- [SQL Server connector demo](./connectors/sql.md)
- [Azure Blob Storage connector demo](./connectors/blob.md)
- [Custom HTTP connector demo](./connectors/custom-http.md)

Recommended order:

1. Start with Key Vault because it is the primary use case.
2. Run SQL and Blob to prove the same network pattern works across multiple first-party connectors.
3. Finish with the custom HTTP connector to show the pattern is not limited to built-in actions.

### Validation checkpoints

After flow creation:

- The Key Vault action returns `demo-secret` with HTTP 200.
- The SQL action returns rows from `dbo.Sales` in `<sqlDatabaseName>`.
- The Blob action returns the content of `demo/hello.txt` from `<storageAccountName>`.
- The custom connector returns the same secret from `GET /secrets/demo-secret?api-version=7.4`.

## Operational notes

- Use [demo-script.md](./demo-script.md) for the customer-facing 20-minute walkthrough.
- Use [security-notes.md](./security-notes.md) to explain RBAC, AAD-only SQL, purge protection, and logging choices.
- Use [cost-control.md](./cost-control.md) for idle-cost framing and cleanup guidance.
- Use `./scripts/05-cleanup.sh` after the demo to remove Azure resources.
