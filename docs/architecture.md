# Architecture

This lab documents a Power Platform virtual network support demo that mirrors the Microsoft Learn virtual network support configuration and uses a United States Power Platform geography backed by paired Azure regions eastus and westus. The design combines delegated subnets, private endpoints, private DNS, a NetworkInjection enterprise policy, and a Managed Environment so makers can reach private Azure services from connectors without exposing those services to the public internet.

## Contents

- [Overview](#overview)
- [Roles and responsibilities](#roles-and-responsibilities)
- [Network topology](#network-topology)
- [Subnet delegation](#subnet-delegation)
- [Two-region pairing](#two-region-pairing)
- [Private DNS](#private-dns)
- [Identity flow](#identity-flow)
- [What gets configured where](#what-gets-configured-where)
- [Learn more](#learn-more)

## Overview

The lab reproduces the role split and network shape shown in the Microsoft Learn setup guidance for [virtual network support for Power Platform](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-setup-configure). An Azure admin creates the Azure network and private endpoint resources, a Power Platform admin links a Managed Environment to the enterprise policy, and a maker builds flows that use private connectivity through supported connectors such as [Azure Key Vault](https://learn.microsoft.com/en-us/connectors/keyvault/), [SQL Server](https://learn.microsoft.com/en-us/connectors/sql/), [Azure Blob Storage](https://learn.microsoft.com/en-us/connectors/azureblob/), and a custom connector. Telemetry infrastructure enables operators to verify traffic flows through the private path—see [monitoring.md](./monitoring.md) for setup and query guidance.

## Roles and responsibilities

### Azure admin

The Azure admin owns the Azure-side resources and permissions:

- Create two VNets in **eastus** and **westus**.
- Create `snet-pp-delegated` and `snet-pep` in each VNet.
- Delegate each `snet-pp-delegated` subnet to `Microsoft.PowerPlatform/enterprisePolicies`.
- Create bidirectional global VNet peering between the two VNets.
- Create the private DNS zones for Key Vault, SQL Database, and Blob Storage, and link each zone to both VNets.
- Create private endpoints for Key Vault, Azure SQL Database, and Storage in the eastus `snet-pep` subnet.
- Disable public network access on those three resources.
- Create the user-assigned managed identity (UAMI) and assign least-privilege data-plane roles.
- Deploy the `Microsoft.PowerPlatform/enterprisePolicies` resource with `kind=NetworkInjection`.

### Power Platform admin

The Power Platform admin owns the environment and policy linkage:

- Create or select a **United States** environment.
- Promote it to a [Managed Environment](https://learn.microsoft.com/en-us/power-platform/admin/managed-environment-overview).
- Confirm the environment geography with `Get-EnvironmentRegion` from the [Microsoft.PowerPlatform.EnterprisePolicies module](https://learn.microsoft.com/en-us/powershell/module/microsoft.powerplatform.enterprisepolicies/).
- Run `Enable-SubnetInjection` to link the environment to `<enterprisePolicyArmId>`.
- Validate that the environment resolves private DNS names and can reach the private endpoints through the delegated subnet path.

### Maker

The maker demonstrates the runtime experience inside the Managed Environment:

- Build Power Automate flows in the linked Managed Environment.
- Configure the [Azure Key Vault connector](./connectors/keyvault.md), [SQL Server connector](./connectors/sql.md), [Azure Blob Storage connector](./connectors/blob.md), and [custom HTTP connector](./connectors/custom-http.md).
- Compare behavior in a non-Managed environment versus the VNet-enabled Managed Environment.
- Use deploy outputs such as `<keyVaultName>`, `<keyVaultUri>`, `<sqlServerFqdn>`, `<sqlDatabaseName>`, and `<storageAccountName>` while setting up connections.

## Network topology

The lab intentionally uses the same paired-region requirement that Learn calls out for the United States: the Power Platform geography is **United States**, and the Azure network footprint is **eastus + westus**. The private endpoints live in the eastus VNet, while the delegated subnet exists in both VNets so Power Platform can fail over consistently across the supported pair. Shared PaaS resources (Key Vault, SQL, Storage) and the resource group also default to `eastus`, keeping the IaC self-documenting and consistent with the primary paired region.

```mermaid
flowchart LR
    subgraph PP[Power Platform geography: United States]
        ME[Managed Environment\nSubnet injection enabled]
        FLOWS[Flows and connectors\nKV / SQL / Blob / Custom HTTP]
        ME --> FLOWS
    end

    subgraph EUS[VNet-East (eastus)]
        EUSD[snet-pp-delegated /27\nDelegated to Microsoft.PowerPlatform/enterprisePolicies]
        EUSEP[snet-pep /27]
        KV[Azure Key Vault\nPrivate endpoint\npublicNetworkAccess=Disabled]
        SQL[Azure SQL Database\nPrivate endpoint\npublicNetworkAccess=Disabled]
        ST[Storage account\nBlob private endpoint\npublicNetworkAccess=Disabled]
        EUSEP --> KV
        EUSEP --> SQL
        EUSEP --> ST
    end

    subgraph WUS[VNet-West (westus)]
        WUSD[snet-pp-delegated /27\nDelegated to Microsoft.PowerPlatform/enterprisePolicies]
        WUSEP[snet-pep /27]
    end

    EUS <--> |Global VNet peering| WUS

    DNS1[privatelink.vaultcore.azure.net]
    DNS2[privatelink.database.windows.net]
    DNS3[privatelink.blob.core.windows.net]

    DNS1 --- EUS
    DNS1 --- WUS
    DNS2 --- EUS
    DNS2 --- WUS
    DNS3 --- EUS
    DNS3 --- WUS

    UAMI[User-assigned managed identity]
    UAMI --> KV
    UAMI --> SQL
    UAMI --> ST

    EP[Enterprise policy\nkind=NetworkInjection]
    EP --> EUSD
    EP --> WUSD
    ME -. linked by Enable-SubnetInjection .-> EP
    FLOWS -. runtime traffic over delegated subnet path .-> EUSD
    FLOWS -. failover-ready path .-> WUSD
```

## Subnet delegation

The delegated subnets are the critical handoff point between Power Platform and your Azure network. Learn describes virtual network support as using [Azure subnet delegation](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview) so Power Platform workloads can run outbound calls inside a subnet that you control. In this lab, both `snet-pp-delegated` subnets are delegated to `Microsoft.PowerPlatform/enterprisePolicies`, which is the resource provider that the enterprise policy uses when `Enable-SubnetInjection` links the environment.

Why this matters:

- It gives Power Platform a supported, private outbound path for connectors and plug-ins.
- It lets your network team enforce routing, DNS, NSG, and firewall policy.
- It avoids broad public allowlists for Azure IP ranges or service tags.
- It preserves the supported failover design for paired regions.

The lab uses `/27` delegated subnets because it is a compact demo, but the production sizing guidance in [vnet support overview](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview#estimating-subnet-size-for-power-platform-environments) recommends sizing based on environment count and runtime IP consumption.

## Two-region pairing

For the United States geography, Learn requires two VNets in different paired regions: **eastus** and **westus**. The same Learn article also provides the broader supported geography-to-region mapping, summarized below for planning purposes.

| Power Platform geography | Required Azure region pair or region |
| --- | --- |
| United States | eastus, westus |
| South Africa | southafricanorth, southafricawest |
| UK | uksouth, ukwest |
| Japan | japaneast, japanwest |
| India | centralindia, southindia |
| France | francecentral, francesouth |
| Europe | westeurope, northeurope |
| Germany | germanynorth, germanywestcentral |
| Switzerland | switzerlandnorth, switzerlandwest |
| Canada | canadacentral, canadaeast |
| Brazil | brazilsouth |
| Australia | australiasoutheast, australiaeast |
| Asia | eastasia, southeastasia |
| UAE | uaenorth |
| Korea | koreasouth, koreacentral |
| Norway | norwaywest, norwayeast |
| Singapore | southeastasia |
| Sweden | swedencentral |
| Italy | italynorth |
| US Government (GCC High only) | usgovtexas, usgovvirginia |

Always validate the target environment with `Get-EnvironmentRegion` before linking it. If the environment region does not map to the VNet pair you built, subnet injection will either fail or produce an unsupported configuration. See [managed-environment-setup.md](./managed-environment-setup.md) and [troubleshooting.md](./troubleshooting.md).

### Why Power Platform needs delegated subnets in BOTH paired regions

A common point of confusion when reading Key Vault / SQL / Storage diagnostic logs in this lab is seeing a `CallerIPAddress` from the **west** delegated subnet (`10.20.0.0/27`) hitting a private endpoint that lives in the **east** VNet. The east delegated subnet (`10.10.0.0/27`) is **not** the only valid source IP — both are.

The reason is built into how Power Platform implements virtual network support for a paired geography:

- The Power Platform service plane is **active in both paired regions** for any geography that has a region pair. For the United States that is `eastus` **and** `westus`. See [VNet support overview — supported regions](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview#supported-regions).
- The `Microsoft.PowerPlatform/enterprisePolicies` resource of `kind=NetworkInjection` references **two** subnet IDs in its `properties.networkInjection.virtualNetworks` array — one per region. `Enable-SubnetInjection` is what wires the Managed Environment to that two-subnet policy.
- At runtime, when a flow, a Power Apps connector call, or a plug-in needs an outbound socket, the Power Platform service picks **whichever region's delegated subnet is healthy and closest to the worker that handles the call**. There is no "primary" subnet from the data plane's perspective — both are first-class egress paths.
- Because every private DNS zone in this lab (`privatelink.vaultcore.azure.net`, `privatelink.database.windows.net`, `privatelink.blob.core.windows.net`) is linked to **both** VNets, the FQDN resolves to the same private endpoint IP regardless of which subnet originated the call. The global VNet peering then carries west-originated traffic into the east VNet where the private endpoint NIC lives.

Concrete consequence observed in the lab: a single Power Apps button press against the Key Vault connector can show up in `AzureDiagnostics` with `CallerIPAddress = 10.20.0.4` (west delegated subnet) on one run and `10.10.0.4` (east delegated subnet) on the next, even though the Key Vault private endpoint is in `vnet-pbinet-dev-east`. **Both are correct. Both prove the private path is being used.** A public IP would be the failure signal.

```mermaid
sequenceDiagram
    autonumber
    participant ME as Managed Environment (US geo)<br/>linked via Enable-SubnetInjection
    participant PPE as Power Platform service plane<br/>(eastus worker)
    participant PPW as Power Platform service plane<br/>(westus worker)
    participant SE as snet-pp-delegated (east)<br/>10.10.0.0/27
    participant SW as snet-pp-delegated (west)<br/>10.20.0.0/27
    participant PEER as Global VNet peering
    participant PE as Key Vault private endpoint<br/>NIC in vnet-pbinet-dev-east
    participant KV as Key Vault<br/>publicNetworkAccess=Disabled

    ME->>PPE: Connector call (run #1)
    PPE->>SE: Outbound socket from 10.10.0.x
    SE->>PE: Resolves privatelink.vaultcore.azure.net via private DNS
    PE->>KV: Authorized data-plane request
    KV-->>ME: Secret value (CallerIPAddress logged as 10.10.0.x)

    ME->>PPW: Connector call (run #2)
    PPW->>SW: Outbound socket from 10.20.0.x
    SW->>PEER: Cross-region hop
    PEER->>PE: Same private endpoint, same private IP
    PE->>KV: Authorized data-plane request
    KV-->>ME: Secret value (CallerIPAddress logged as 10.20.0.x)
```

Operational checklist this drives:

- Treat **either** `10.10.0.0/27` **or** `10.20.0.0/27` as a successful private-path signal in Key Vault, SQL, Storage, and NSP logs.
- Keep both VNets linked to every `privatelink.*` zone — dropping the west link would cause west-originated calls to fall back to public DNS and silently break.
- Keep global VNet peering between east and west healthy — see [troubleshooting.md](./troubleshooting.md) for the peering symptom matrix.
- When sizing the delegated subnets for production, size **both** for peak — failover is not "west sits idle until east dies", it is active/active load distribution.

## Private DNS

Each private DNS zone is linked to **both** VNets, even though the three private endpoints are created in VNet-East. That dual linking matters because the enterprise policy references delegated subnets in both regions, and any runtime path or failover path still needs to resolve the service FQDNs to private IP addresses instead of public ones.

The lab uses these private DNS zones:

- `privatelink.vaultcore.azure.net` for Key Vault, following [Azure Key Vault private link guidance](https://learn.microsoft.com/en-us/azure/key-vault/general/private-link-service).
- `privatelink.database.windows.net` for Azure SQL Database private endpoints.
- `privatelink.blob.core.windows.net` for Azure Blob Storage private endpoints.

If a zone is linked to only one VNet, DNS resolution from the other region can return a public IP or fail entirely. That is why [troubleshooting.md](./troubleshooting.md) includes a dedicated DNS symptom section.

## Identity flow

The demo uses one user-assigned managed identity so the data-plane story is consistent across services. The UAMI principal ID is surfaced as `<userAssignedIdentityPrincipalId>` in deploy outputs and should receive least-privilege assignments at the narrowest practical scope.

Recommended assignments in this lab:

- **Key Vault Secrets User** on the vault so the connector or calling identity can read `demo-secret`.
- **Storage Blob Data Reader** on the storage account or demo container so the Blob connector can read `demo/hello.txt`.
- **Azure SQL logical server Microsoft Entra admin** set to the UAMI so the environment can use Microsoft Entra-based SQL access without SQL logins.

Identity flow at runtime:

1. A flow runs inside the Managed Environment.
2. Power Platform sends the outbound call through the delegated subnet selected by the enterprise policy.
3. Private DNS resolves the target service FQDN to the private endpoint IP.
4. The target service authorizes the caller through Microsoft Entra ID and Azure RBAC or Entra-based SQL administration.

## What gets configured where

### Deployed by Bicep

The infrastructure deployment creates the Azure-side topology and emits the outputs referenced throughout this doc set:

- VNets, subnets, peering, and subnet delegation.
- Private DNS zones and links.
- Key Vault, Azure SQL Database, and Storage account.
- Private endpoints in VNet-East `snet-pep`.
- User-assigned managed identity.
- Enterprise policy resource with `kind=NetworkInjection`.
- Key Vault secrets `demo-secret` and `sql-connection-string`.
- Outputs: `<enterprisePolicyArmId>`, `<keyVaultName>`, `<keyVaultUri>`, `<sqlServerFqdn>`, `<sqlDatabaseName>`, `<storageAccountName>`, `<userAssignedIdentityPrincipalId>`.

### Configured by the PowerShell script

`./scripts/02-configure-pp-vnet.ps1` is expected to complete the Power Platform side:

- Install or import the Power Platform enterprise policies module if needed.
- Validate the environment region.
- Call `Enable-SubnetInjection -EnvironmentId <id> -PolicyArmId <enterprisePolicyArmId>`.
- Confirm the environment is now linked to the enterprise policy.

### Configured by the maker

The maker configures runtime artifacts after the environment is linked:

- Create or update flows in the Managed Environment.
- Build connector connections using the placeholders from deployment outputs.
- Prepare demo data that is not created by Bicep today, such as SQL objects and sample rows like `dbo.Sales`, and blob content such as `demo/hello.txt`.
- Run the validation flows documented in [deployment-guide.md](./deployment-guide.md) and [demo-script.md](./demo-script.md).

## Diagnostics & observability

After deployment, operators can verify the private path is working:

- **Active diagnostics** — Use the PowerShell cmdlets in [troubleshooting.md](./troubleshooting.md) to test DNS resolution, network connectivity, and TLS handshakes from the delegated subnet to each resource. See [troubleshooting.md: reference](./troubleshooting.md#reference-diagnostic-cmdlets) for the cmdlet reference table.
- **Passive monitoring** — Enable Network Security Perimeter in Learning mode and VNet flow logs to capture all traffic (successful and denied). See [monitoring.md](./monitoring.md) for setup and KQL queries that confirm private path usage and identify issues.

Both are complementary: diagnostics answer *whether* a connection works; monitoring answers *how it flows* through the network layers and *why it fails*.

## Learn more

- [Virtual network support for Power Platform overview](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview)
- [Set up and configure virtual network support for Power Platform](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-setup-configure)
- [Virtual network support for Power Platform whitepaper](https://learn.microsoft.com/en-us/power-platform/admin/virtual-network-support-whitepaper)
- [Managed Environments overview](https://learn.microsoft.com/en-us/power-platform/admin/managed-environment-overview)
- [Microsoft.PowerPlatform.EnterprisePolicies PowerShell module](https://learn.microsoft.com/en-us/powershell/module/microsoft.powerplatform.enterprisepolicies/)

> This lab is **Power Platform VNet support**. For Power BI or Fabric private data access via VNet Data Gateway, see [expansion-roadmap.md](./expansion-roadmap.md).
