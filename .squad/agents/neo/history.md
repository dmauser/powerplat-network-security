# Project Context

- **Owner:** dmauser
- **Project:** powerplat-network-security — Power Platform VNet support lab. Reproduces the supported config where Power Platform (Power Automate / Power Apps / Dataverse) reaches private Azure resources (Key Vault, Azure SQL, Storage) via VNet-injected subnets in the US geography (eastus + westus paired regions).
- **Stack:** Bicep (subscription-scope IaC), Azure CLI, PowerShell 7, Microsoft.PowerPlatform.EnterprisePolicies module, Mermaid, GitHub Actions (bicep validate). Active docs at repo root + docs/; legacy Fabric MPE content in archive/ (read-only).
- **Key resources:** 2x VNet w/ snet-pp-delegated + snet-pep, 3x private DNS zones (vaultcore/database/blob) linked to both VNets, Key Vault (publicNetworkAccess=Disabled), Azure SQL serverless, Storage GPv2, UAMI, Microsoft.PowerPlatform/enterprisePolicies kind=NetworkInjection, Managed Environment linked via Enable-SubnetInjection.
- **Created:** 2026-05-20

## Learnings

### 2026-05-20T13:55:18-05:00 — validation review pass

- Replaced operator-box `dig` checks in `scripts/03-validate-network.sh` with stronger Azure-side checks that compare Private DNS A records to private endpoint IPs and verify the zones are linked to both VNets that contain `snet-pp-delegated`.
- Tightened negative-path assertions so the validator now expects explicit denial outcomes: Key Vault public REST `403`, SQL public TCP 1433 denied, Blob anonymous GET `403`, and Blob SAS-over-public `403`.
- Updated `docs/demo-script.md` to separate workstation denial probes from Managed Environment allow-path proofs, with dated runnable commands and connector-specific expected results.
- Connector guides still need richer verification prose, so validator-authored test steps were written to `.squad/decisions/inbox/` for Niobe to merge instead of editing her docs directly.

## Team Update — 2026-05-20T19:17:03Z

**Follow-up sweep completed.** Trinity resolved westus3 + AzureServices flags by changing `defaultLocation` to eastus and setting `bypass = 'None'` on Key Vault/Storage modules (see `.squad/orchestration-log/2026-05-20T19-17-03Z-trinity.md`). Niobe merged connector test steps, removed archive references, and cleaned diagram (see `.squad/orchestration-log/2026-05-20T19-17-03Z-niobe.md`). All 5 outstanding items now resolved; decisions merged into `.squad/decisions.md`. See `.squad/log/2026-05-20T19-17-03Z-followup-sweep.md` for round summary.