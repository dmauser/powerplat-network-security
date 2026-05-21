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
- **2026-05-20T15:36:31-05:00** — `Set-AdminPowerAppEnvironmentApplicationInsights` does NOT exist in `Microsoft.PowerPlatform.EnterprisePolicies` v0.17.0 or `Microsoft.PowerApps.Administration.PowerShell`. Use the BAP admin REST API PATCH (`api-version=2023-06-01`) instead. Auth via `az account get-access-token --resource https://service.powerapps.com/`.
- **2026-05-20T15:36:31-05:00** — PP environment AI binding idempotency: GET environment first (`properties.applicationInsightsId`), compare to desired resource ID, skip PATCH if match. Replace silently if different (unlike enterprise policy swap, which is guarded — AI binding swap is safe).
- **2026-05-20T15:36:31-05:00** — Workspace-based App Insights (`IngestionMode: 'LogAnalytics'`) requires `Application_Type: 'web'` for PP integration. The `applicationInsightsKey` field in the BAP PATCH body accepts either the legacy instrumentation key or the full connection string; prefer connection string for workspace-based resources.
- **2026-05-20T15:36:31-05:00** — Connector telemetry caveats: Tenant-level analytics, per-connector "Enable diagnostics" in make.powerapps.com, and canvas app republish after AI binding are manual PPAC/maker steps not automatable via REST today. Environment-level binding and binding verification are fully automatable.

## Learnings — 2026-05-20T17:05:00-05:00 (Phase 2 run)

- **2026-05-20T17:05:00-05:00** — `Microsoft.PowerPlatform.EnterprisePolicies v0.17.0` references `$Global:InPesterExecution`, `$Global:PrereqsChecked`, and `$Global:ImportedTypes` without guarding for unset state. With `Set-StrictMode -Version Latest`, `Import-Module` throws. Fix: pre-seed all three before `Import-Module`. `ImportedTypes` must be `[string[]]@()`, not `$false`.
- **2026-05-20T17:05:00-05:00** — The module installs `Az.Accounts 5.3.0`, `Az.Resources 8.1.1`, `Az.KeyVault 6.4.0`, `Az.Network 7.22.0` as exact-version dependencies via interactive Y/N prompts. These are one-time installs. Future runs skip this step silently.
- **2026-05-20T17:05:00-05:00** — The EP module calls `Get-AzContext -ListAvailable` before every operation. If no Az PowerShell context exists (freshly installed Az.Accounts), it falls through to interactive browser auth even when az CLI is already authenticated. Bridge pattern: `Connect-AzAccount -AccessToken (az account get-access-token token) -AccountId <upn> -Tenant <tid>` before first EP module call. Added as `Ensure-AzContext` function in script 02.
- **2026-05-20T17:05:00-05:00** — The EP module's `Get-EnvironmentRegion` builds a per-environment DNS hostname `{envId-nodashes-prefix}.{2char-suffix}.environment.api.powerplatform.com`. This hostname is NOT a wildcard DNS record — it only exists if the environment is provisioned and registered in PP's routing plane. A 404 from `GET /scopes/admin/environments/{id}` means the ME ID is wrong or belongs to a different tenant.
- **2026-05-20T17:05:00-05:00** — `az login` with a personal MSA (Hotmail) account returns an empty PP environment list from `/scopes/admin/environments` and 404 for specific environment lookups. Power Platform admin operations require a work/school account with the **Power Platform Administrator** or **Global Administrator** Entra role. Verify with `az account show --query user.name` — if it's `@hotmail.com` or `@outlook.com`, re-login with the correct tenant.
- **2026-05-20T17:05:00-05:00** — Bicep outputs may omit `appInsightsResourceId` and `appInsightsInstrumentationKey` if the IaC module doesn't explicitly output them. Script 02 reads these under `Set-StrictMode -Version Latest` and fails if missing. Workaround: derive `resourceId` via `az resource show` and parse `InstrumentationKey=` from the connection string, then patch `.azure/last-deploy-outputs.json`. Long-term fix: add these to `infra/main.bicep` outputs.

## Learnings — 2026-05-20T18:50:00-05:00 (Phase 2 run — second session)

- **2026-05-20T18:50:00-05:00** — BAP enterprise policy link API (`POST /enterprisePolicies/NetworkInjection/link`) requires the calling user to have `ManageProtectionKeys` permission in the environment. This maps to the **Power Platform Administrator** Entra role (tenant-wide) OR the **System Administrator** Dataverse security role (environment-scope). `Global Reader` + Azure Subscription Owner is NOT sufficient.
- **2026-05-20T18:50:00-05:00** — The correct full environment ID for default PP environments has a `Default-` prefix: `Default-{tenantId}`. In this tenant the environment ID is `Default-ebf541ac-cacf-4a40-b46e-1accc3810ef8`. The bare GUID alone returns 404.
- **2026-05-20T18:50:00-05:00** — `NewNetworkInjection` in `lifecycleOperationsEnforcement.allowedOperations` is only present when the environment has no Dataverse instance yet. After Dataverse provisioning it changes to `SwapNetworkInjection` + `RevertNetworkInjection`. The underlying BAP API endpoint (`POST /enterprisePolicies/NetworkInjection/link`) is the same for both cases.
- **2026-05-20T18:50:00-05:00** — Provisioning a Dataverse database via `POST /provisionInstance` (with `CreateDatabase` permission) does NOT grant the caller `ManageProtectionKeys`. The Dataverse System Administrator role grants `prvAssignRole` and data access, but the BAP API checks PP-platform-level permissions separately. You need the Power Platform Administrator Entra role to call the enterprise policy link endpoint.
- **2026-05-20T18:50:00-05:00** — CDX tenant (`MngEnvMCAP423074.onmicrosoft.com`) breakglass account is `ms-breakglass@MngEnvMCAP423074.onmicrosoft.com`. It is the only Global Administrator in the tenant. CDX credentials can be retrieved from the CDX/Transform portal. The `admin@` account only has `Global Reader` Entra role despite being Azure Subscription Owner.
- **2026-05-20T18:50:00-05:00** — The `managedenvironments-ar-tenant-connector` service principal (appId `14735148-5162-46ef-99a4-c1923d08a2cc`) has Global Administrator role in the tenant. It is a Microsoft-managed service app for managed environments integration. Its credentials cannot be retrieved without Global Admin or Application Administrator Entra role.

## Punch List — Queued for Tank (2026-05-20T21:06:15-05:00)

**P2 — Link ME to Policy (BLOCKED on role grant):** After operator grants Power Platform Administrator role to admin@... (see Phase 2 Prep section in decisions.md for step-by-step), resume ME policy link:
1. Run `scripts/02-configure-pp-vnet.ps1 -EnvironmentId Default-ebf541ac-cacf-4a40-b46e-1accc3810ef8`
2. Script will call `Enable-SubnetInjection` and PATCH App Insights binding
3. Verify enterprise policy `healthStatus` transitions to `Running`

**P4 — Verify Demo Artifacts:** Post-deploy, confirm (or create):
- KV secret `demo-secret` (via `az keyvault secret list` from inside delegated subnet)
- Blob `demo/hello.txt` (via Storage browser or `az storage blob list`)
- SQL table `dbo.Sales` with seed data (create via SQL admin credentials)

## Team Update — 2026-05-20T18:55:18Z

**Repo review sweep completed.** All 5 agents delivered findings, fixes, and decisions. See `.squad/decisions.md` for the complete merged decision set. Orchestration logs created at `.squad/orchestration-log/2026-05-20T18-55-18Z-*.md` and team session log at `.squad/log/2026-05-20T18-55-18Z-repo-review-sweep.md`. Your script hardening completed and idempotency confirmed. Follow-ups pending: validation script parameterization, demo artifact provisioning, broader doc sync for version gates and re-run safety.

## Team Update — 2026-05-20T15:50:00-05:00

**Monitoring trio coordination complete.** App Insights (workspace-based) wired to Trinity's LAW; script 02 now binds PP Managed Environment to App Insights via BAP admin REST PATCH (idempotent, workaround for missing cmdlet in v0.17.0). Script 04 enables connector telemetry + prints canonical KQL queries for Niobe's docs/monitoring.md. Zero integration conflicts; all scripts parse-clean. See `.squad/orchestration-log/2026-05-20T15-50-00Z-tank-1.md` and `.squad/skills/pp-app-insights-wiring/SKILL.md` for REST API pattern (reusable for future PP integrations).