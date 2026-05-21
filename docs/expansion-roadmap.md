# Expansion roadmap

This roadmap captures the most natural follow-on conversations after the base lab is working. The lab itself focuses on Power Platform virtual network support for Managed Environments; the ideas below show how to extend the same story into adjacent products, hybrid networking, additional connectors, and production hardening.

## Contents

- [Overview](#overview)
- [Power BI and Fabric via VNet Data Gateway](#power-bi-and-fabric-via-vnet-data-gateway)
- [Dataverse plug-in sample with Key Vault](#dataverse-plug-in-sample-with-key-vault)
- [Hybrid on-premises connectivity](#hybrid-on-premises-connectivity)
- [Additional connector ideas](#additional-connector-ideas)
- [Function App for App Insights dependency tracing](#function-app-for-app-insights-dependency-tracing)
- [Single-region and non-US variants](#single-region-and-non-us-variants)
- [Production hardening](#production-hardening)
- [Learn more](#learn-more)

## Overview

The base lab is intentionally narrow: it proves connector traffic from a Managed Environment to private Azure services through delegated subnets. Once that is clear, the next design discussion is usually about product fit, hybrid reach, or how to make the topology production-ready.

## Power BI and Fabric via VNet Data Gateway

This is the most important audience switch to call out. Power Platform virtual network support is the right story for connector and plug-in runtime traffic from Power Platform environments. For **Power BI** and **Fabric** private data access, the recommended path is generally the **VNet Data Gateway** model rather than the subnet-injection model documented in this lab.

Use this when customers ask why the repository is named `powerbi-network-security` but the lab focuses on Power Platform:

- The current lab demonstrates **Power Platform VNet support**.
- A future expansion can add a parallel lab for **Power BI / Fabric private data access via VNet Data Gateway**.
- Those are related but distinct architectures, as explained in the [Power Platform overview FAQ](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview#whats-the-difference-between-a-virtual-network-data-gateway-and-azure-virtual-network-support-for-power-platform).

## Dataverse plug-in sample with Key Vault

A useful engineering expansion is a small C# Dataverse plug-in that reads a secret from Key Vault by using the same private network path and managed identity model. That would let the repo show both supported runtime categories from the [overview article](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview): connectors and Dataverse plug-ins.

## Hybrid on-premises connectivity

The same VNet-enabled Managed Environment can be extended to on-premises systems by connecting the VNets back to the datacenter:

- ExpressRoute for higher-throughput, enterprise-grade private connectivity.
- Site-to-site VPN for simpler hybrid lab setups.

In that expansion, Power Platform still enters the network through the delegated subnet path. The hybrid circuit simply extends the reachable private address space beyond Azure.

## Additional connector ideas

Once the base four demos are working, consider adding more supported services:

- Azure Queues
- Azure File Storage
- HTTP with Microsoft Entra ID (preauthorized)
- AI Search
- Snowflake
- Databricks

Those ideas map directly to the supported-services list in the [virtual network support overview](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview#supported-services).

## Function App for App Insights dependency tracing

The Power Apps Key Vault connector runs in the Power Platform service plane and is not visible to a customer-owned Application Insights instance — `dependencies | where target contains "vault.azure.net"` returns zero rows even when the connector path is healthy. To close that observability gap, add a small VNet-integrated **Azure Function App** that calls Key Vault from code you own and instrument.

Planned shape:

- HTTP-triggered Function (PowerShell 7.4 or .NET 8 isolated) that reads `demo-secret` and returns 200.
- System-assigned managed identity with `Key Vault Secrets User` on `kv-pbinet-dev-*`.
- Regional VNet integration into a new `snet-funcapp` `/27` in `vnet-pbinet-dev-east` (separate from `snet-pp-delegated` and `snet-pep`).
- Inbound private endpoint on `snet-pep`, `publicNetworkAccess = Disabled`.
- Same `appi-pbinet-dev` Application Insights instance — no new resource needed.

This is the **Demo Part 4** scaffolding tracked in [`demos/keyvault-demo.md`](./demos/keyvault-demo.md#demo-part-4--custom-code-path-with-app-insights-dependency-tracking-planned). Owners: Trinity (Bicep module `infra/modules/funcapp.bicep`), Tank (`scripts/01-deploy.sh` wiring + smoke test), Niobe (doc expansion once deployed).

## Single-region and non-US variants

This lab uses the hard-coded United States mapping of **eastus + westus**. Variants for other geographies can follow the same structure with different paired regions, for example:

- **Europe** -> `westeurope + northeurope`
- **UK** -> `uksouth + ukwest`
- **Japan** -> `japaneast + japanwest`

Always drive the final choice from `Get-EnvironmentRegion` and the [supported regions table](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview#supported-regions).

## Production hardening

Typical next steps for a production-oriented design:

- Separate Managed Environments for production and nonproduction.
- Use a larger delegated subnet CIDR than the demo `/27` where scale requires it.
- Add an Azure NAT Gateway if public outbound access is still required for approved scenarios, matching the [setup guidance](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-setup-configure).
- Add Azure Policy and tagging standards for governance.
- Centralize diagnostics in Log Analytics.
- Document failover and environment lifecycle operations explicitly.

## Learn more

- [Virtual network support overview](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview)
- [Managed Environments overview](https://learn.microsoft.com/en-us/power-platform/admin/managed-environment-overview)
- [Virtual network support whitepaper](https://learn.microsoft.com/en-us/power-platform/admin/virtual-network-support-whitepaper)
