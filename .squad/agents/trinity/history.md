# Project Context

- **Owner:** dmauser
- **Project:** powerplat-network-security — Power Platform VNet support lab. Reproduces the supported config where Power Platform (Power Automate / Power Apps / Dataverse) reaches private Azure resources (Key Vault, Azure SQL, Storage) via VNet-injected subnets in the US geography (eastus + westus paired regions).
- **Stack:** Bicep (subscription-scope IaC), Azure CLI, PowerShell 7, Microsoft.PowerPlatform.EnterprisePolicies module, Mermaid, GitHub Actions (bicep validate). Active docs at repo root + docs/; legacy Fabric MPE content in archive/ (read-only).
- **Key resources:** 2x VNet w/ snet-pp-delegated + snet-pep, 3x private DNS zones (vaultcore/database/blob) linked to both VNets, Key Vault (publicNetworkAccess=Disabled), Azure SQL serverless, Storage GPv2, UAMI, Microsoft.PowerPlatform/enterprisePolicies kind=NetworkInjection, Managed Environment linked via Enable-SubnetInjection.
- **Created:** 2026-05-20

## Learnings

- 2026-05-20T13:55:18-05:00 — Validated every `infra/**/*.bicep` file with `bicep build` and `bicep lint`; the current subscription-scope main template and RG-scope modules compile cleanly.
- 2026-05-20T13:55:18-05:00 — `scripts/01-deploy.sh` had Windows CRLF line endings that broke `bash -n`; normalizing the script to LF and enforcing `*.sh text eol=lf` in `.gitattributes` keeps the deploy script portable.
- 2026-05-20T14:17:03-05:00 — **Region default:** Changed `defaultLocation` from `westus3` → `eastus` in `infra/main.bicep` and `infra/parameters/dev.parameters.json`. Chose option (a): align default to the primary paired region (eastus) so the IaC is self-documenting and no footgun exists for operators who accept defaults. `westus3` had no documented justification (no quota or feature dependency) and contradicted the architecture narrative. Bicep build + lint both pass clean after the change.
- 2026-05-20T14:17:03-05:00 — **AzureServices bypass:** Changed `networkAcls.bypass` from `'AzureServices'` → `'None'` on both Key Vault (`infra/modules/keyvault.bicep`) and Storage (`infra/modules/storage.bicep`). Rationale: the `bypass` property is a public-endpoint firewall setting; with `publicNetworkAccess = 'Disabled'` the public endpoint never accepts traffic, making any bypass value functionally moot. Setting `'None'` explicitly removes the misleading exception and signals defense-in-depth intent. No Microsoft Learn article documents a Power Platform VNet support scenario that requires `AzureServices` bypass when public access is off — all runtime traffic flows through the delegated subnet → private endpoint path. If public access were re-enabled, this would need re-evaluation.
- 2026-05-20T14:17:03-05:00 — **Bicep gotcha:** Edit tool requires exact whitespace match including indentation level. When `old_str` mismatches whitespace the edit silently fails — always verify the indentation in the view output before writing the edit call.

## Team Update — 2026-05-20T18:55:18Z

**Repo review sweep completed.** All 5 agents delivered findings, fixes, and decisions. See `.squad/decisions.md` for the complete merged decision set. Orchestration logs created at `.squad/orchestration-log/2026-05-20T18-55-18Z-*.md` and team session log at `.squad/log/2026-05-20T18-55-18Z-repo-review-sweep.md`. Your bicep validation successes are confirmed; line-ending fixes applied. Follow-ups pending: westus3 location justification, AzureServices bypass testing, provider registration ownership.