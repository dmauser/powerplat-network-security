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

- 2026-05-20T15:36:31-05:00 — **LAW + diagnostic-settings pattern:** Deployed Log Analytics workspace (SKU PerGB2018, parameterized retention 30–730 days) as a dependency module before all consumers. Public network access left Enabled for lab simplicity; noted AMPLS option in module comment for production hardening.
- 2026-05-20T15:36:31-05:00 — **Bicep generic diagnostic settings workaround:** Bicep requires statically-typed resource references for extension resource scopes; `Microsoft.Insights/diagnosticSettings` must be attached to a known resource type. The workaround is a `Microsoft.Resources/deployments` nested ARM deployment in `diagnosticSettings.bicep`, where the ARM template `scope` property accepts a dynamic string. Uses `expressionEvaluationOptions.scope=inner`. Suppressed `no-deployments-resources` lint rule with `#disable-next-line` and an explanatory comment. Build and lint both exit 0 with zero warnings after suppression.
- 2026-05-20T15:36:31-05:00 — **KV log categories chosen:** `AuditEvent` (every authenticated KV operation with caller identity + source IP — THE signal for private-vs-public path confirmation) and `AzurePolicyEvaluationDetails` (policy compliance visibility). Metric: `AllMetrics`. Storage blob: `StorageRead/Write/Delete` + `Transaction` metric. SQL DB: `SQLSecurityAuditEvents`, `Errors`, `Timeouts` + `Basic` + `InstanceAndAppAdvanced` metrics. PEs and VNets: metrics only (`AllMetrics`) — no log categories exist for these resource types.
- 2026-05-20T15:36:31-05:00 — **Alert philosophy (opt-in by default):** `enableAlerts = false` default prevents email spam in lab environments while still deploying the action group stub unconditionally. Operators set `enableAlerts = true` in parameters when they are ready to receive notifications. The 5-in-5-min threshold for KV denial alerts balances sensitivity against false positives in shared lab subscriptions. PE metric alerts use `PEConnectionsConnected` (the documented metric for active PE connections, analogous to health status). The KV log-search alert uses `AzureDiagnostics` table (universal, works with both legacy and resource-specific diagnostic schema settings).
- 2026-05-20T15:36:31-05:00 — **Canonical LAW output names confirmed:** `logAnalyticsWorkspaceName` and `logAnalyticsWorkspaceId` exposed from `main.bicep`. Niobe references these in `docs/monitoring.md`; Tank references them for App Insights correlation. Added `sqlDatabaseId` output to `sql.bicep` to support SQL DB diagnostic settings scope.

**Repo review sweep completed.** All 5 agents delivered findings, fixes, and decisions. See `.squad/decisions.md` for the complete merged decision set. Orchestration logs created at `.squad/orchestration-log/2026-05-20T18-55-18Z-*.md` and team session log at `.squad/log/2026-05-20T18-55-18Z-repo-review-sweep.md`. Your bicep validation successes are confirmed; line-ending fixes applied. Follow-ups pending: westus3 location justification, AzureServices bypass testing, provider registration ownership.

- **2026-05-20T15:50:00-05:00 — Monitoring trio coordination complete.** LAW + diagnostic settings wired to Key Vault, SQL Database, Storage blob, 3x Private Endpoints, and 2x VNets; canonical outputs (`logAnalyticsWorkspaceName`, `logAnalyticsWorkspaceId`) delivered. Tank (App Insights binding) and Niobe (operator guide + KQL queries) both adopted the output names with zero conflicts. Alerts module opt-in by default prevents lab noise. See `.squad/orchestration-log/2026-05-20T15-50-00Z-trinity-2.md` and `.squad/decisions.md` Monitoring section for details. All Bicep clean (build + lint pass 0).

- **2026-05-20T17:10:48-05:00 — Phase 1 Azure plane deployed to rg-pbinet-dev-eastus.** Deployment `pp-vnet-kv-demo-202605201710` succeeded on subscription `43d55e51`. 22 resources deployed (SQL skipped — East US capacity constraint). Outputs written to `.azure/last-deploy-outputs.json` including snet-pp-delegated subnet IDs for Tank's Phase 2. Decision inbox: `.squad/decisions/inbox/trinity-deploy-2026-05-20.md`.

  IaC bugs found and fixed:

  - **Bicep `[` → `[[` escaping (critical):** Bicep double-escapes `[` in all object-literal strings and `loadJsonContent()` variables, making ARM expressions into literal strings at runtime. The generic `diagnosticSettings.bicep` nested-ARM approach is broken for Bicep v0.42.x. Fix: use typed `resource` declarations with `scope:` per module.
  - **VNet link `location: 'global'` required:** `Microsoft.Network/privateDnsZones/virtualNetworkLinks` needs explicit `location: 'global'` — does NOT inherit from parent zone.
  - **PE diagnostic settings not supported:** `microsoft.network/privateendpoints` returns `ResourceTypeNotSupported`. Monitor PEs via Azure Monitor Metrics (PEConnectionsConnected) directly.
  - **East US SQL capacity:** `RegionDoesNotAllowProvisioning` at deploy time. Use `deploySql=true` when capacity is available or add `sqlLocation` param to target `eastus2`.
  - **Subscription context drift:** sync/async PowerShell shells can have different active subscriptions. Always `az account show` per shell. Fix: `az account set --subscription`.
  - **App Insights unwired:** `infra/modules/appInsights.bicep` existed but was never called from `main.bicep`. Wired in this session.

- 2026-05-21 — **NSP module structure:** `infra/modules/nsp.bicep` now owns the perimeter, profile, and full NSP diagnostic settings fan-out to Log Analytics; `infra/modules/nsp-association.bicep` uses `existing` perimeter/profile references and defaults each association to `Learning` for audit-only rollout.
- 2026-05-21 — **Flow logs cross-RG scope pattern:** `infra/modules/flow-logs.bicep` is deployed with `scope: resourceGroup('NetworkWatcherRG')` and attaches flow logs under the existing `NetworkWatcher_<region>` resource for each VNet region. The lab resource group only hosts the dedicated flow-logs storage account.
- 2026-05-21 — **API versions used:** Pinned `Microsoft.Network/networkSecurityPerimeters@2023-08-01-preview`, `Microsoft.Network/networkSecurityPerimeters/profiles@2023-08-01-preview`, `Microsoft.Network/networkSecurityPerimeters/resourceAssociations@2023-11-01`, `Microsoft.Network/networkWatchers@2024-05-01`, and `Microsoft.Network/networkWatchers/flowLogs@2024-05-01` per Morpheus's audit spec.

## Punch List — Queued for Trinity (2026-05-20T21:06:15-05:00)

**P1 — Deploy SQL (retry or fallback):** East US was at capacity during Phase 1 deployment. Options:
- **Option A (preferred):** Retry. Set `deploySql=true` in `infra/parameters/dev.parameters.json` (or command-line override) and re-run `scripts/01-deploy.sh` when East US SQL capacity becomes available.
- **Option B (fallback):** Change `defaultLocation` to `eastus2` and redeploy (note: this will place SQL in a different region than shared resources).

**Success criteria:**
- SQL Server appears in `rg-pbinet-dev-eastus`
- PE-SQL deployed with IP in `snet-pep` (10.10.1.x/27)

## Session: 2026-05-21 — Coordinator Planning + Trinity Part 4 Scoping

**Task:** Document Part 4 expansion scope (Function App + Cosmos DB connector scenario).

**Part 4 Ownership for Trinity:**
- **Module:** `infra/modules/funcapp.bicep` — Azure Functions host with VNet integration to `snet-pp-delegated` (same pattern as Managed Environment, enabling private Cosmos DB connector calls)
- **Bicep skeleton:** App Service Plan (dynamic tier), Function App with VNet integration, system-managed identity, private endpoint for Cosmos DB (follow existing PE pattern from keyvault.bicep + storage.bicep)
- **Outputs:** funcAppId, funcAppName, cosmosDbPeId (for cross-doc linking and NSP association candidate)
- **Link from:** `docs/expansion-roadmap.md` → `infra/modules/funcapp.bicep` (TBD)
- **Post-deployment:** Tank scripts `07-*` will include Function App startup and Cosmos DB connector smoke test

**Expected delivery:** Phase 4 (after Part 3 completion + NSP validation)

**Pattern:** Reuse the approved VNet integration + PE + private DNS + NSP association pattern from KV/SQL/Storage for consistency.
- DNS A record in `privatelink.database.windows.net` → PE-SQL private IP
- SQL diagnostic settings (`diag-sql`) created and streaming to LAW
- `.azure/last-deploy-outputs.json` contains non-empty `sqlServerFqdn` + `sqlDatabaseName`

## Team Update — 2026-05-21T19:30:00Z

**KV demo RBAC automation baked into IaC:** Bicep `demoUserPrincipalIds` parameter added to `infra/modules/keyvault.bicep` and wired through `infra/main.bicep`; emits per-user role assignments for `Key Vault Secrets User` at deploy time.