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

## Team Update — 2026-05-20T18:55:18Z

**Repo review sweep completed.** All 5 agents delivered findings, fixes, and decisions. See `.squad/decisions.md` for the complete merged decision set. Orchestration logs created at `.squad/orchestration-log/2026-05-20T18-55-18Z-*.md` and team session log at `.squad/log/2026-05-20T18-55-18Z-repo-review-sweep.md`. Your findings on architecture scope, westus3 location drift, and AzureServices bypass are now in team decisions waiting for follow-up actions.
