# Demo script

This script is a 20-minute customer-facing walkthrough that frames Power Platform virtual network support as the supported way to let Managed Environments reach private Azure services without exposing those services to the internet. The flow of the demo is to first show the problem in a non-Managed environment, then show the same connector actions succeeding from the lab's Managed Environment after subnet injection is enabled, while explicit negative-path probes keep proving that the public endpoints stay blocked.

## Contents

- [Overview](#overview)
- [Pre-demo checklist](#pre-demo-checklist)
- [Command spot-checks](#command-spot-checks)
- [20-minute walkthrough](#20-minute-walkthrough)
- [Talking points](#talking-points)
- [After the meeting](#after-the-meeting)

## Overview

Use this script with [architecture.md](./architecture.md), [deployment-guide.md](./deployment-guide.md), and the connector walkthroughs in [keyvault.md](./connectors/keyvault.md), [sql.md](./connectors/sql.md), [blob.md](./connectors/blob.md), and [custom-http.md](./connectors/custom-http.md). Plan to have both a non-Managed environment and the lab's Managed Environment ready before you start, so you can show the before-and-after experience without spending time on setup during the meeting.

## Pre-demo checklist

Before the call:

- Have a **non-Managed** environment ready for the failure demonstration.
- Have the lab's **Managed Environment** already linked to `<enterprisePolicyArmId>`.
- Pre-create or prepare the Key Vault secret `demo-secret`, the SQL table `dbo.Sales`, and the Blob file `demo/hello.txt`.
- Keep the deployment outputs handy: `<keyVaultName>`, `<keyVaultUri>`, `<sqlServerFqdn>`, `<sqlDatabaseName>`, `<storageAccountName>`.
- Warm the SQL database once shortly before the meeting so the first query does not spend the demo on serverless resume latency.
- Run `./scripts/03-validate-network.sh` and keep the output open in another terminal tab.
- Open [architecture.md](./architecture.md) in one tab and the Azure portal in another.
- If possible, pre-open Key Vault diagnostic logs, Storage diagnostics, or NSG flow logs so you can quickly show private-IP traffic evidence.

## Command spot-checks

Use these commands before the meeting and keep the expected output handy. They were spot-checked for this repo on **2026-05-20**.

### Public denial probes from the operator workstation

These commands prove that the public endpoints stay blocked. They do **not** prove the allow path from inside `snet-pp-delegated`; the Managed Environment flow runs do that.

```bash
curl -sS -o /dev/null -w "%{http_code}\n" "https://<keyVaultName>.vault.azure.net/secrets/demo-secret?api-version=7.4"
# Expected: 403

curl -sS -o /dev/null -w "%{http_code}\n" "https://<storageAccountName>.blob.core.windows.net/demo/hello.txt"
# Expected: 403
```

```powershell
Test-NetConnection -ComputerName '<sqlServerFqdn>' -Port 1433 |
  Select-Object ComputerName, RemotePort, TcpTestSucceeded
# Expected: TcpTestSucceeded = False
```

### Storage SAS denial probe

Use this once before the meeting if you want a stronger Blob negative-path proof than anonymous access alone.

```bash
RESOURCE_GROUP="$(az resource list --name <storageAccountName> --resource-type Microsoft.Storage/storageAccounts --query '[0].resourceGroup' -o tsv)"
ACCOUNT_KEY="$(az storage account keys list -g "$RESOURCE_GROUP" -n <storageAccountName> --query '[0].value' -o tsv)"
EXPIRY="$(pwsh -NoLogo -NoProfile -Command "(Get-Date).ToUniversalTime().AddMinutes(15).ToString('yyyy-MM-ddTHH:mmZ')")"
SAS_TOKEN="$(az storage blob generate-sas --account-name <storageAccountName> --account-key "$ACCOUNT_KEY" --container-name demo --name hello.txt --permissions r --expiry "$EXPIRY" -o tsv)"
curl -sS -o /dev/null -w "%{http_code}\n" "https://<storageAccountName>.blob.core.windows.net/demo/hello.txt?$SAS_TOKEN"
# Expected: 403
```

## 20-minute walkthrough

### 0-2 minutes: set the stage

1. Open [architecture.md](./architecture.md) and show the network topology diagram.
2. Name the three roles clearly:
   - **Azure admin** builds VNets, private endpoints, DNS, and the enterprise policy.
   - **Power Platform admin** links the Managed Environment to that policy.
   - **Maker** builds flows that now run through the delegated subnet path.
3. Explain the hard requirement for this lab: **United States** Power Platform geography with **eastus + westus** Azure regions.
4. Set audience expectations: public probes should keep failing from your workstation while the Managed Environment flows succeed because they execute from inside the delegated subnet path described in [Power Platform virtual network support](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview).

### 2-5 minutes: show the problem without VNet support

1. Open the non-Managed environment.
2. Run a simple flow that uses the **Azure Key Vault** connector to read `demo-secret`.
3. Show the failure result: action status **Failed** with a `403 Forbidden`-style outcome.
4. If time allows, show the matching workstation probe returning `403` from `https://<keyVaultName>.vault.azure.net/secrets/demo-secret?api-version=7.4`.
5. Frame the problem: the same resource is private, public access is disabled, and the non-Managed environment does not have the delegated subnet path required by [Power Platform virtual network support](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview).

Suggested narration:

> Without virtual network support, Power Platform is trying to reach a private-only service from an environment that is not linked to our enterprise policy. The connector is valid, but the runtime path is not.

### 5-9 minutes: switch to the Managed Environment and repeat Key Vault

1. Switch to the lab's Managed Environment.
2. Open the equivalent flow or create it quickly by following [connectors/keyvault.md](./connectors/keyvault.md).
3. Run the flow using the same secret name, `demo-secret`.
4. Show the success result with HTTP `200` and the returned secret value.
5. Say the contrast out loud: the public REST probe is still `403`, but the Managed Environment action succeeds because it is using the delegated subnet path.
6. Point back to the architecture:
   - Environment is managed.
   - `Enable-SubnetInjection` linked it to `<enterprisePolicyArmId>`.
   - Private DNS resolves `<keyVaultName>.vault.azure.net` to a private endpoint IP for the runtime.
   - The request stays on the Microsoft backbone and reaches the private endpoint.

### 9-12 minutes: demonstrate SQL connector

1. Open the SQL flow from [connectors/sql.md](./connectors/sql.md).
2. Show **SQL Server -> Get rows (V2)**.
3. Use `<sqlServerFqdn>` and `<sqlDatabaseName>`.
4. Run the flow and show rows from `dbo.Sales`.
5. Show or mention the workstation negative probe: `Test-NetConnection` to `<sqlServerFqdn>:1433` returns `TcpTestSucceeded = False`.
6. Mention that the same delegated subnet path works for [SQL Server connector support](https://learn.microsoft.com/en-us/connectors/sql/), not just Key Vault.

### 12-14 minutes: demonstrate Blob connector

1. Open the Blob flow from [connectors/blob.md](./connectors/blob.md).
2. Show **Azure Blob Storage -> Get blob content (V2)**.
3. Use `<storageAccountName>`, container `demo`, blob `hello.txt`.
4. Run the flow and show the returned file content.
5. Show or mention both negative probes:
   - Anonymous GET to `https://<storageAccountName>.blob.core.windows.net/demo/hello.txt` returns `403`.
   - A valid SAS on that same public URL also returns `403`.
6. Reinforce that the blob is readable only through the private endpoint path used by the Managed Environment runtime.

### 14-16 minutes: demonstrate a custom HTTP connector

1. Open the custom connector built with [connectors/custom-http.md](./connectors/custom-http.md).
2. Show that the host is `<keyVaultName>.vault.azure.net`.
3. Run `GET /secrets/demo-secret?api-version=7.4`.
4. Show the HTTP `200` result.
5. Explain the point of the demo: the network path is not limited to a single built-in connector. Any HTTPS API that the environment can reach privately, and that you authenticate correctly, can follow the same pattern.

### 16-18 minutes: prove it is private

1. Open the `./scripts/03-validate-network.sh` output and call out three things:
   - Key Vault public REST is `403`.
   - SQL public TCP 1433 is denied.
   - Blob anonymous and SAS-over-public both return `403`.
2. Show the script's Azure-side DNS checks that compare Private DNS A records to the private endpoint IPs.
3. Open Key Vault diagnostics, Storage diagnostics, NSG flow logs, or similar monitoring evidence.
4. Show private IP addresses or private-endpoint-based traffic patterns.
5. Reinforce that `publicNetworkAccess=Disabled` is still set on Key Vault, SQL, and Storage.

### 18-20 minutes: wrap up with governance and fit

Close with these points:

- This is the supported outbound private-access model for Power Platform connectors and plug-ins in Managed Environments.
- Region pairing matters: for this lab, US means **eastus + westus**.
- Managed Environment entitlement and licensing matter for production planning.
- Negative-path tests matter: do not assume "private" unless the public endpoints are still denied while the Managed Environment run succeeds.
- For Power BI or Fabric private data access, the design conversation changes; see [expansion-roadmap.md](./expansion-roadmap.md).

## Talking points

> **Cost**  
> The Azure footprint is intentionally small for a demo, and the biggest variable cost is usually the database tier if you leave it running. Managed Environment licensing is a Power Platform licensing discussion, not an Azure meter, so I keep the price conversation qualitative and point customers to the current pricing page in [cost-control.md](./cost-control.md).

> **When should I use VNet Data Gateway instead?**  
> Use Power Platform virtual network support when the workload is connector or plug-in runtime traffic from Power Platform itself. Use VNet Data Gateway for Power BI and Power Platform dataflows, which follow a different product path called out in the [Power Platform overview FAQ](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview#whats-the-difference-between-a-virtual-network-data-gateway-and-azure-virtual-network-support-for-power-platform).

> **What about on-premises systems?**  
> The same pattern extends to on-premises resources if your VNets are connected back to the datacenter over ExpressRoute or site-to-site VPN. The Power Platform runtime still uses the delegated subnet path; your hybrid network just determines where that private route goes next.

> **What happens if the subnet fills up?**  
> Power Platform runtime containers consume IPs from the delegated subnet, so exhausted subnets eventually block scale or new allocations. For production, size the subnet using the guidance in the [overview article](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview#estimating-subnet-size-for-power-platform-environments), and if you need to change a delegated range later, plan that before go-live or engage support.

## After the meeting

- Share the implementation docs starting with [deployment-guide.md](./deployment-guide.md).
- Use [troubleshooting.md](./troubleshooting.md) to handle common follow-up issues.
- Use [security-notes.md](./security-notes.md) and [cost-control.md](./cost-control.md) for governance and operations follow-up.
