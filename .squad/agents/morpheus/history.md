# Project Context

- **Owner:** dmauser
- **Project:** powerplat-network-security — Power Platform VNet support lab. Reproduces the supported config where Power Platform (Power Automate / Power Apps / Dataverse) reaches private Azure resources (Key Vault, Azure SQL, Storage) via VNet-injected subnets in the US geography (eastus + westus paired regions).
- **Stack:** Bicep (subscription-scope IaC), Azure CLI, PowerShell 7, Microsoft.PowerPlatform.EnterprisePolicies module, Mermaid, GitHub Actions (bicep validate). Active docs at repo root + docs/; legacy Fabric MPE content in archive/ (read-only).
- **Key resources:** 2x VNet w/ snet-pp-delegated + snet-pep, 3x private DNS zones (vaultcore/database/blob) linked to both VNets, Key Vault (publicNetworkAccess=Disabled), Azure SQL serverless, Storage GPv2, UAMI, Microsoft.PowerPlatform/enterprisePolicies kind=NetworkInjection, Managed Environment linked via Enable-SubnetInjection.
- **Created:** 2026-05-20

## Learnings

- 2026-05-20T13:55:18-05:00 — Reviewed the repo end-to-end for architecture/security posture. Confirmed the core pattern is still two delegated VNets (eastus + westus), three private DNS zones linked to both VNets, eastus private endpoints, RBAC Key Vault, AAD-only SQL, and a `NetworkInjection` enterprise policy that references both delegated subnets.
- 2026-05-20T13:55:18-05:00 — Found drift between the narrative and implementation: shared resources default to `westus3`, the Mermaid diagram hard-codes `rg-pbinet-dev`, Key Vault and Storage still carry `AzureServices` ACL bypass settings, and the validation script is narrower than the docs claim.
- 2026-05-20T13:55:18-05:00 — Applied doc-scope fixes in `README.md`, `docs/architecture.md`, and `docs/security-notes.md` to clarify what Bicep really deploys, distinguish post-deploy demo prep from infra deployment, and tighten the private-path validation language.

- 2026-05-21T14:39:11-05:00 — NSP topology decision: Single perimeter in eastus with one profile covering all three PaaS resources (KV, SQL, Storage). Learning mode for audit-only PE traffic capture. API versions: `2023-08-01-preview` for NSP/profile, `2023-11-01` for resourceAssociations. Key gotchas: (1) NSP requires `AllowNSPInPublicPreview` feature flag registration + re-register Microsoft.Network RP; (2) SQL association targets logical server not database; (3) Diagnostic settings go on the NSP resource itself (not PaaS resources) — logs land in `NSPAccessLogs` table; (4) NSP in Learning mode coexists safely with `publicNetworkAccess: Disabled`; (5) Log latency is 5-15 min. Spec written to `.squad/decisions/inbox/morpheus-nsp-audit-spec.md`.
- 2026-05-21T14:39:11-05:00 — VNet flow logs + Traffic Analytics decision: Use VNet flow logs (not NSG flow logs) since lab has no NSGs. Flow logs are child resources of `NetworkWatcher_<region>` in `NetworkWatcherRG` — modules must scope there. Dedicated SA needed with `publicNetworkAccess: Enabled` (NW writes there). Traffic Analytics auto-deploys `NetworkMonitoring` solution and creates `AzureNetworkAnalytics_CL` table — no manual solution install needed. API: `Microsoft.Network/networkWatchers/flowLogs@2024-05-01`. Format v2, retention 7d at flow log level, 30d lifecycle on SA.

## Team Update — 2026-05-20T19:17:03Z

**Follow-up sweep completed.** Trinity resolved westus3 + AzureServices flags by changing `defaultLocation` to eastus and setting `bypass = 'None'` on Key Vault/Storage modules (see `.squad/orchestration-log/2026-05-20T19-17-03Z-trinity.md`). Niobe merged connector test steps, removed archive references, and cleaned diagram (see `.squad/orchestration-log/2026-05-20T19-17-03Z-niobe.md`). All 5 outstanding items now resolved; decisions merged into `.squad/decisions.md`. See `.squad/log/2026-05-20T19-17-03Z-followup-sweep.md` for round summary.
