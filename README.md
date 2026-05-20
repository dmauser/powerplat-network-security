# Private Power Platform Access to Azure Key Vault (and friends) via VNet support

[![Bicep validate](https://github.com/dmauser/powerbi-network-security/actions/workflows/bicep-validate.yml/badge.svg)](https://github.com/dmauser/powerbi-network-security/actions/workflows/bicep-validate.yml)

A low-cost, end-to-end lab that reproduces the supported configuration in the Microsoft Learn diagram
[**Virtual Network support configurations**](https://learn.microsoft.com/en-us/power-platform/admin/media/vnet-support/vnet-support-configurations.png#lightbox) — i.e., how a **Power Platform** flow (Power Automate / Power Apps / Dataverse plug-in) reaches **private** Azure resources over VNet-injected subnets.

The primary demo is **Azure Key Vault** with `publicNetworkAccess=Disabled`, called from the built-in Power Automate **Azure Key Vault** connector. Three additional connectors (SQL Server, Azure Blob Storage, custom HTTP) are exercised against the same delegated subnets to prove the pattern generalizes.

> This is a **Power Platform** demo. For Power BI / Fabric private access via **VNet Data Gateway**, see [`docs/expansion-roadmap.md`](./docs/expansion-roadmap.md).
> The previous Fabric Managed Private Endpoint lab content lives in [`archive/`](./archive).

---

## What gets deployed

![Architecture](./assets/architecture-diagram.mmd)

| Component | Notes |
|---|---|
| 2× VNet (eastus, westus) | US Power Platform geography requires **two** paired regions. Each has `snet-pp-delegated /27` + `snet-pep /27`. Bidirectional global peering. |
| 3× Private DNS zones | `privatelink.{vaultcore.azure.net, database.windows.net, blob.core.windows.net}`. **Linked to both VNets.** |
| Azure Key Vault | RBAC mode, public access **Disabled**, purge protection. Seeded with `demo-secret` and `sql-connection-string`. |
| Azure SQL DB | Serverless GP, 1h auto-pause, AAD-only auth, public access **Disabled**. Seeded with `dbo.Sales`. |
| Storage account | GPv2, public access **Disabled**, blob container `demo` with `hello.txt`. |
| 3× Private endpoints | All in VNet-East / `snet-pep`. Reached from the other VNet via peering. |
| User-assigned managed identity | Used as KV Secrets User, Storage Blob Data Reader, and SQL AAD admin. |
| `Microsoft.PowerPlatform/enterprisePolicies` | kind = `NetworkInjection`, references both delegated subnets. |
| Power Platform Managed Environment | Provisioned manually (US geo), linked via `Enable-SubnetInjection`. |

Idle Azure cost is **a few USD/month** — see [`docs/cost-control.md`](./docs/cost-control.md).

---

## Prerequisites

- An Azure subscription where you can create RGs and register resource providers.
- An existing **Power Platform Managed Environment** in the **United States** geography. See [`docs/managed-environment-setup.md`](./docs/managed-environment-setup.md). ME licensing (per-user Power Platform plan) is a hard prereq.
- Local tools: `az` (Azure CLI ≥ 2.60), `bicep` (via `az bicep`), `pwsh` 7+, `jq`, `bash`.
- PowerShell module `Microsoft.PowerPlatform.EnterprisePolicies` (the deploy script installs it for you).

---

## Quick start

```bash
# 0. One-time setup: register RPs + feature flag, verify tools
./scripts/00-prereqs.sh

# 1. Deploy the Azure side (Bicep, subscription scope)
./scripts/01-deploy.sh

# 2. Link the enterprise policy to your Managed Environment
pwsh ./scripts/02-configure-pp-vnet.ps1 -EnvironmentId <your-env-guid>

# 3. Validate
./scripts/03-validate-network.sh

# 4. Build a flow following one of the connector guides:
#    docs/connectors/keyvault.md       (primary use case)
#    docs/connectors/sql.md
#    docs/connectors/blob.md
#    docs/connectors/custom-http.md

# 5. Clean up when done
./scripts/05-cleanup.sh --purge-kv --yes
```

Full walkthrough: [`docs/deployment-guide.md`](./docs/deployment-guide.md).

---

## Repo layout

```
infra/                  Bicep (subscription-scope main + modules)
scripts/                Bash + PowerShell automation
docs/                   Architecture, deployment, demo script, troubleshooting
docs/connectors/        Per-connector maker steps
assets/                 Mermaid diagrams (roles, topology, sequence)
.github/workflows/      CI: bicep build + what-if (no deploy)
archive/                Previous Fabric-MPE lab content (read-only reference)
```

---

## Roles in this configuration

Mirrors the Microsoft Learn role diagram:

![Roles](./assets/roles-configuration.mmd)

- **Azure admin** — creates the VNets, delegated subnets, private endpoints, DNS zones, and the enterprise policy. Needs `Network Contributor` on the RG.
- **Power Platform admin** — promotes the environment to Managed and runs `Enable-SubnetInjection`. Needs `Power Platform Administrator` in Microsoft Entra.
- **Maker** — builds the flow, picks the built-in connector, points it at the private resource by FQDN.

---

## Documentation index

- Architecture → [`docs/architecture.md`](./docs/architecture.md)
- Deployment guide → [`docs/deployment-guide.md`](./docs/deployment-guide.md)
- Managed Environment setup → [`docs/managed-environment-setup.md`](./docs/managed-environment-setup.md)
- 20-min demo script → [`docs/demo-script.md`](./docs/demo-script.md)
- Connector how-tos → [`docs/connectors/`](./docs/connectors/)
- Troubleshooting → [`docs/troubleshooting.md`](./docs/troubleshooting.md)
- Cost control → [`docs/cost-control.md`](./docs/cost-control.md)
- Security notes → [`docs/security-notes.md`](./docs/security-notes.md)
- Expansion roadmap (VNet DG, Fabric, on-prem) → [`docs/expansion-roadmap.md`](./docs/expansion-roadmap.md)

---

## References

- [Virtual Network support overview — Power Platform](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview)
- [Set up and configure Virtual Network support](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-setup-configure)
- [Virtual Network support white paper](https://learn.microsoft.com/en-us/power-platform/admin/virtual-network-support-whitepaper)
- [Managed Environments overview](https://learn.microsoft.com/en-us/power-platform/admin/managed-environment-overview)
- [Key Vault private link](https://learn.microsoft.com/en-us/azure/key-vault/general/private-link-service)

## License

MIT — see [`LICENSE`](./LICENSE).
