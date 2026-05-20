# Project Context

- **Owner:** dmauser
- **Project:** powerplat-network-security — Power Platform VNet support lab. Reproduces the supported config where Power Platform (Power Automate / Power Apps / Dataverse) reaches private Azure resources (Key Vault, Azure SQL, Storage) via VNet-injected subnets in the US geography (eastus + westus paired regions).
- **Stack:** Bicep (subscription-scope IaC), Azure CLI, PowerShell 7, Microsoft.PowerPlatform.EnterprisePolicies module, Mermaid, GitHub Actions (bicep validate). Active docs at repo root + docs/; legacy Fabric MPE content in archive/ (read-only).
- **Key resources:** 2x VNet w/ snet-pp-delegated + snet-pep, 3x private DNS zones (vaultcore/database/blob) linked to both VNets, Key Vault (publicNetworkAccess=Disabled), Azure SQL serverless, Storage GPv2, UAMI, Microsoft.PowerPlatform/enterprisePolicies kind=NetworkInjection, Managed Environment linked via Enable-SubnetInjection.
- **Created:** 2026-05-20

## Learnings

- **2026-05-20T13:55:18-05:00** — `scripts/00-prereqs.sh` had CRLF-sensitive shell parsing issues in Bash, so Tank normalized the shell scripts to LF-safe content and added `ERR` traps for actionable failures.
- **2026-05-20T13:55:18-05:00** — `scripts/02-configure-pp-vnet.ps1` now pins `Microsoft.PowerPlatform.EnterprisePolicies` to `0.17.0`, validates the deploy outputs path relative to the repo, and treats an already-linked matching policy as a clean no-op.
- **2026-05-20T13:55:18-05:00** — `Get-SubnetInjectionEnterprisePolicy -EnvironmentId` is the safest pre-check for rerunnable subnet injection because it surfaces the currently linked enterprise policy before `Enable-SubnetInjection` is invoked.

## Team Update — 2026-05-20T18:55:18Z

**Repo review sweep completed.** All 5 agents delivered findings, fixes, and decisions. See `.squad/decisions.md` for the complete merged decision set. Orchestration logs created at `.squad/orchestration-log/2026-05-20T18-55-18Z-*.md` and team session log at `.squad/log/2026-05-20T18-55-18Z-repo-review-sweep.md`. Your script hardening completed and idempotency confirmed. Follow-ups pending: validation script parameterization, demo artifact provisioning, broader doc sync for version gates and re-run safety.