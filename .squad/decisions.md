# Squad Decisions

**Last Updated:** 2026-05-21T14:27:57-05:00  
**Source:** Lab audit + Phase 1 deployment + Phase 2 prep completion + Phase 2 attempt #2 (Trial env blocker + BAP REST confirmation) + Phase 2 success (ME linked, App Insights binding blocked) + KV demo guide structure + live-verification findings + KV connector formula fix + KV demo RBAC automation

## Phase 2 Outcome (Tank, 2026-05-21T04:20:00Z)

### 🟢 ME Linked to Enterprise Policy (SUCCEEDED)

**Environment:** `Default-ebf541ac-cacf-4a40-b46e-1accc3810ef8` ("Contoso (default)")  
**Enterprise Policy:** `ep-pbinet-dev` (ARM ID in `.azure/last-deploy-outputs.json`)  
**Method:** BAP REST bypass (direct `POST .../enterprisePolicies/NetworkInjection/link`)  
**Lifecycle op:** `NewNetworkInjection: Succeeded` (op `0ce043ef`, 2026-05-21T04:05:12Z)  
**Confirmed idempotent:** Re-run → `SwapNetworkInjection: Succeeded` (op `68dc19ad`)

**New prerequisite discovered:** Default PP environments require governance tier upgrade from `Basic` → `Standard` before `NewNetworkInjection` is allowed. `scripts/02-configure-pp-vnet.ps1` now includes this step automatically via `Set-AdminPowerAppEnvironmentGovernanceConfiguration`.

**ARM healthStatus:** Remains `Undetermined` — expected. Authoritative confirmation is the BAP lifecycle op state, not ARM healthStatus.

### 🔴 App Insights Binding — No Automated Path

`applicationInsightsId` and related fields do not exist in `EnvironmentProperties` on any
BAP API version (2016-11-01 through 2024-05-01). All REST PATCH attempts return `400 InvalidRequestContent`. The earlier decision entry (2026-05-20T15:36:31-05:00) claiming REST PATCH works was incorrect.

**Current state:** Binding must be configured manually via PPAC admin center:
**admin.powerplatform.microsoft.com → Environments → Settings → Product → Features → Application Insights**

`scripts/02-configure-pp-vnet.ps1` AI binding section updated to skip and print PPAC portal instructions.

---

### US Paired-Region Scope (Morpheus decision)

**Scope:** Power Platform US geography requires **eastus + westus** paired-region architecture for:
- VNets and delegated `snet-pp-delegated` subnets (REQUIRED)
- Private DNS zones linked to both VNets (REQUIRED)
- Microsoft.PowerPlatform/enterprisePolicies `kind=NetworkInjection` referencing both delegated subnets (REQUIRED)

**Shared PaaS Placement:** Separate deployment choice; must be documented explicitly when it differs from paired regions.

**Consequences:**
- Architecture docs distinguish required network-pair scope from parameterized shared-resource placement.
- Diagrams avoid hard-coded names; reflect actual IaC choices.
- Validation logic references paired-region requirements explicitly.

---

## Infrastructure Findings (Morpheus, Trinity)

### 🟢 Shared-Resource Location Drift (RESOLVED)

**Finding:** `infra/main.bicep` defaults shared resources to `westus3`, contradicting the `eastus+westus` paired-region narrative.

**Resolution (Trinity):** Changed `defaultLocation` from `westus3` to `eastus`.
- **Rationale:** `westus3` had no documented justification (no quota, feature, or architecture requirement). It was a footgun for operators accepting defaults. Aligning to `eastus` makes the IaC self-documenting and consistent with docs narrative.
- **Files modified:** `infra/main.bicep`, `infra/parameters/dev.parameters.json`, `docs/architecture.md`, `README.md`.
- **Verification:** `az bicep build` and `az bicep lint` both pass clean; `grep -ri "westus3" infra/ docs/ README.md` returns zero matches.

### 🟢 Key Vault and Storage Bypass Settings (RESOLVED)

**Finding:** Both modules declared `networkAcls.bypass = 'AzureServices'` despite `publicNetworkAccess = 'Disabled'`.

**Resolution (Trinity):** Changed `bypass` to `'None'` on both Key Vault and Storage.
- **Rationale:** The `bypass` property is a public-endpoint firewall setting. With public access disabled, the bypass is functionally inert and creates confusion about trusted exception paths that don't actually exist. Setting `'None'` explicitly signals defense-in-depth intent. No Microsoft Learn documentation requires `AzureServices` bypass for Power Platform VNet support with public access disabled; all runtime traffic flows through delegated subnet → private endpoint path.
- **Caveat:** If public access is ever re-enabled (e.g., break-glass tooling), this decision must be revisited.
- **Files modified:** `infra/modules/keyvault.bicep`, `infra/modules/storage.bicep`, `docs/security-notes.md` (with inline rationale in modules; updated security doc).
- **Verification:** `az bicep build` and `az bicep lint` both pass clean.

### 🟢 Bicep Validation & Compliance

**Status:** `bicep build` and `bicep lint` pass for all modules after region and bypass fixes.

**Verified by:** Trinity (2026-05-20T14:17:03-05:00)

---

## Validation & Demo Gaps

### 🟡 Validation Script Narrowness

**Finding:** `scripts/03-validate-network.sh` hard-codes resource group `rg-pbinet-dev`, validates only public reachability/DNS, does NOT check:
- Enterprise policy subnet references
- Private DNS zone links to both VNets
- Private endpoint contents

**Docs claim:** Full validation coverage (per `docs/deployment-guide.md`)

**Owners:** Tank + Neo

**Follow-up:**
- Parameterize resource group lookup from `.azure/last-deploy-outputs.json`
- Add explicit checks for enterprise policy, DNS zones, private endpoints.

### 🟡 Demo Artifact Provisioning

**Finding:** Bicep creates Key Vault secrets, but NOT SQL objects (`dbo.Sales`) or blob content (`demo/hello.txt`).

**Docs assume:** These artifacts pre-exist.

**Owners:** Tank + Niobe

**Follow-up:**
- Automate prep in post-deploy scripts, OR
- Clearly mark as manual pre-demo preparation.

### 🟢 Network Validation Rewrite (Neo)

**Fixed:**
- Updated `scripts/03-validate-network.sh` to compare Private DNS A records to private endpoint IPs.
- Verify private DNS zone links to both VNets containing `snet-pp-delegated`.
- Expect explicit deny outcomes: Key Vault `403`, SQL TCP 1433 blocked, Blob anonymous `403`, Blob SAS-public `403`.

---

## Documentation Findings (Niobe)

### 🟢 Audit Complete — 100% Compliance

**Scope:** 13 active markdown files (README.md, docs/*, docs/connectors/*)  
**Status:** Production-ready with excellent hygiene.

**Compliance checks (all ✅ PASS):**
- Summary paragraphs + Contents sections + body structure
- Pure GitHub-flavored Markdown (no HTML)
- ATX headings only
- Fenced code blocks with language tags (`bash`, `powershell`, `bicep`, `mermaid`, `text`)
- Placeholder usage (no hard-coded tenant IDs)
- Microsoft Learn inline citations
- Aggressive cross-linking

**Issues found and fixed:**
1. Missing Contents section in README.md — FIXED
2. Broken link to `archive/` — See decision below

**Connector verification steps (MERGED):** Niobe merged Neo's test probes into all 4 connector docs under "## Testing the private path" sections:
- `docs/connectors/keyvault.md` — Added deny/allow probes and private DNS checks
- `docs/connectors/sql.md` — Added deny/allow probes and private DNS checks
- `docs/connectors/blob.md` — Added deny/allow probes and private DNS checks
- `docs/connectors/custom-http.md` — Added deny/allow probes and private DNS checks
- All now follow standardized connector-walkthrough template: summary → contents → overview → before-start → build/create → expected-result → **testing-the-private-path** → notes/troubleshooting → learn-more.

---

## Directory & Content Decisions

### 🟢 Archive Directory Status (RESOLVED)

**Problem:** `archive/` referenced in docs but does NOT exist (zero git history).

**Decision (Niobe):** Option (a) — Remove all archive references.

**Rationale:** 
- No legacy content to preserve (confirmed via `git log --all -- archive/`)
- No future use case documented
- Broken links are a docs hygiene violation
- Clean slate aligns with "active content at repo root" principle

**Action Taken:**
- Removed archive references from `README.md` (removed line + table row)
- Removed archive references from `.github/copilot-instructions.md`
- Result: 0 broken links pointing to archive/ (or any non-existent resource)

### 🟢 Architecture Diagram Cleanup (RESOLVED)

**Finding (Niobe):** `assets/architecture-diagram.mmd` hard-coded resource group name `rg-pbinet-dev`.

**Action Taken:** Replaced with generic placeholder `"Azure subscription"` to align with convention of using deploy-output placeholders instead of hard-coded values.

**Validation:** Mermaid syntax confirmed valid; no broken brackets or flowchart references.

---

## Script & Tooling Updates

### 🟢 Prereqs Script Hardened (Tank)

**Fixed in `scripts/00-prereqs.sh`:**
- Added explicit tool version gates.
- Enforced LF line endings.
- Added `ERR` trap for failure handling.

**Registered providers (Learn-documented PP VNet prereqs):**
- `Microsoft.PowerPlatform`
- `Microsoft.Sql`
- `Microsoft.KeyVault`
- `Microsoft.Storage`
- `Microsoft.Network`
- `enterprisePoliciesPreview` feature flag

**Follow-up:** Decide whether extra infra-only providers (e.g., `Microsoft.ManagedIdentity`) should be registered in `scripts/01-deploy.sh` or documented elsewhere.

### 🟢 PP VNet Link Script Hardened (Tank)

**Fixed in `scripts/02-configure-pp-vnet.ps1`:**
- Pinned `Microsoft.PowerPlatform.EnterprisePolicies` module to v0.17.0.
- Made script re-run safe (same policy = no-op path).
- Added region validation for US geography.

### 🟢 Network Validation Rewritten (Neo)

**Updated `scripts/03-validate-network.sh`:**
- A-record + zone-link verification for private DNS.
- Explicit deny-path checks (Key Vault, SQL, Blob).
- Honest scope statement: bash validator can't test inside delegated subnet; Managed Environment runs required for allow-path proof.

### 🟢 Cleanup Script Fixed (Tank)

**Fixed `scripts/05-cleanup.sh`:**
- Removed hardcoded resource group reference.
- Made deletion targets parameterized.

---

## Doc Sync & Update Decisions

### 🟡 Broader Doc Alignment (Tank finding for Niobe)

**Affected docs:**
- `docs/deployment-guide.md`
- `docs/troubleshooting.md`
- `README.md`

**Decision needed:** Explicitly call out:
1. Version gates in `00-prereqs.sh`
2. `enterprisePoliciesPreview` registration wording for `Microsoft.PowerPlatform/accounts/enterprisePolicies`
3. `02-configure-pp-vnet.ps1` re-run safety when same policy already linked

### 🟡 Provider Registration Ownership (Tank finding for Trinity)

**Scope:** `Microsoft.ManagedIdentity` and other infra-only provider registrations.

**Decision needed:** Should `scripts/01-deploy.sh` self-register these, or should the requirement be documented elsewhere in Trinity's deployment workflow?

---

## Monitoring & Observability Decisions (2026-05-20)

### 🟢 Monitoring Plumbing Complete (Trinity)

**Date:** 2026-05-20T15:36:31-05:00

New IaC modules deliver Log Analytics workspace (LAW) + diagnostic settings + alert infrastructure:

**New modules:**
- `infra/modules/logAnalytics.bicep` — central data sink
- `infra/modules/diagnosticSettings.bicep` — reusable diagnostic-settings attacher (uses nested ARM as workaround for Bicep extension-resource scoping)
- `infra/modules/alerts.bicep` — action group + 3 opt-in alert rules

**Modified:**
- `infra/modules/sql.bicep` — added `sqlDatabaseId` output
- `infra/main.bicep` — wired LAW, 8 diagnostic fan-outs, alerts
- `infra/parameters/dev.parameters.json` — added `logAnalyticsRetentionDays: 30`, `enableAlerts: false` (opt-in default rationale: lab environments often share subscriptions)

**Diagnostic targets (8 total):**
| Target | Log Categories | Metrics |
|---|---|---|
| Key Vault | `AuditEvent`, `AzurePolicyEvaluationDetails` | `AllMetrics` |
| Storage blob | `StorageRead`, `StorageWrite`, `StorageDelete` | `Transaction` |
| SQL Database | `SQLSecurityAuditEvents`, `Errors`, `Timeouts` | `Basic`, `InstanceAndAppAdvanced` |
| PE–KV, PE–SQL, PE–Storage | _(none)_ | **Metrics only** (see note below) |
| VNet eastus, VNet westus | _(none)_ | `AllMetrics` |

> **Private Endpoint Diagnostic Settings Limitation (CORRECTED — 2026-05-21T23:45:18-05:00):** Azure platform does **NOT** support `Microsoft.Insights/diagnosticSettings` on `microsoft.network/privateendpoints` resource type. API returns `ResourceTypeNotSupported`. PE telemetry is available via Azure Monitor **Metrics** blade only (metric: `PEConnectionsConnected` shows active connection count). See `infra/modules/private-endpoint.bicep` inline documentation. The `diagnosticSettings.bicep` module was updated to skip PE resources; PE health is verified through the Metrics visual and KQL queries in `docs/monitoring.md`.

**Canonical output names (LOCKED — no renaming without coordination):**
- `logAnalyticsWorkspaceName` — workspace human-readable name
- `logAnalyticsWorkspaceId` — full ARM resource ID

**Bicep constraint note:** `diagnosticSettings.bicep` uses `Microsoft.Resources/deployments` nested ARM (Bicep limitation); `#disable-next-line no-deployments-resources` suppression inline. `az bicep build` and `az bicep lint` both pass 0.

**Verification:**
```bash
az bicep build --file infra/main.bicep   # exit 0
az bicep lint  --file infra/main.bicep   # exit 0, 0 warnings
```

### 🟢 Power Platform → Application Insights Wiring (Tank)

**Date:** 2026-05-20T15:36:31-05:00

Tank wired Power Platform telemetry pipeline to shared LAW workspace for end-to-end PP ↔ Azure resource correlation:

**Decisions:**
1. **Application Insights shape:** Workspace-based (`IngestionMode: 'LogAnalytics'`, `WorkspaceResourceId` → Trinity's LAW). Module at `infra/modules/appInsights.bicep`.
2. **Cross-module output naming:** Aligned with Trinity; expects `logAnalyticsWorkspaceId` from LAW module.
3. **PP AI binding: REST API (not cmdlet).** `Set-AdminPowerAppEnvironmentApplicationInsights` does not exist in module v0.17.0. Use Power Platform admin REST PATCH instead:
   ```
   PATCH https://api.bap.microsoft.com/providers/
       Microsoft.BusinessAppPlatform/scopes/admin/environments/{envId}
       ?api-version=2023-06-01
   Body: {
     "properties": {
       "applicationInsightsId": "<appInsightsResourceId>",
       "applicationInsightsKey": "<connectionString>"
     }
   }
   ```
4. **Idempotency:** Script 02 GETs environment first; skips PATCH if same AI already bound. Replacement is safe (unlike policy swap).
5. **Connector telemetry scope:**
   - ✅ Environment-level AI binding (script 02 REST PATCH)
   - ✅ AI binding verification (script 04 read-only GET)
   - ✅ KQL queries in LAW (script 04, referenced from `docs/monitoring.md`)
   - ❌ Tenant-level analytics (PPAC UI only)
   - ❌ Custom connector "Enable diagnostics" (per-connector make.powerapps.com UI)
   - ❌ Canvas app republish after AI binding (manual)

**Files added:**
- `infra/modules/appInsights.bicep` — workspace-based AI resource
- `scripts/04-enable-connector-telemetry.ps1` — verification + guidance script

**Files modified:**
- `infra/main.bicep` — appInsights module + `logAnalyticsWorkspaceId` param + 4 outputs
- `scripts/02-configure-pp-vnet.ps1` — AI binding REST PATCH section after Enable-SubnetInjection
- `.squad/skills/pp-app-insights-wiring/SKILL.md` — reusable pattern

**Verification:** Both scripts parse-clean; Bicep build clean.

### 🟢 Monitoring Documentation Complete (Niobe)

**Date:** 2026-05-20T15:36:31-05:00

`docs/monitoring.md` (17.5 KB) delivered as comprehensive operator guide for PP → Azure telemetry:

**Structure (9 sections):**
1. What gets logged (diagnostic categories table)
2. Telemetry architecture (Mermaid flowchart: App Insights + resource diagnostics → shared LAW)
3. 6 operator KQL queries:
   - (a) Is PP reaching KV over private endpoint?
   - (b) Public-endpoint denial attempts?
   - (c) Audit trail (who/what accessed secret)?
   - (d) Private endpoint health?
   - (e) DNS resolution verification?
   - (f) End-to-end correlation (App Insights ↔ backend)?
4. Dashboard setup (pinning to dashboards or Workbooks)
5. Alerts (enable, configure action group)
6. Troubleshooting decision tree (validation script → audit → PE health → DNS → PP setup re-link)
7. Cost note (LAW PerGB2018 SKU, 30d retention default, controls)
8. References (8 Microsoft Learn citations)

**Cross-links added (8 files, 11 new links):**
- README.md — added monitoring.md to Documentation index
- docs/architecture.md — telemetry plane reference
- docs/security-notes.md — expanded logging section
- docs/deployment-guide.md — post-validation step
- docs/connectors/{keyvault, sql, blob, custom-http}.md — "Verify via telemetry" sub-bullets

**Assumptions made (Trinity/Tank work will verify):**
1. LAW output: `logAnalyticsWorkspaceName`, `logAnalyticsWorkspaceId`
2. App Insights output: `appInsightsName`
3. Diagnostic categories: Trinity confirms KV, SQL, Storage categories in monitoring.bicep
4. PE metrics only (no logs) — platform limitation per Microsoft Learn
5. VNet CIDRs: eastus 10.10.0.0/16, westus 10.20.0.0/16; delegated: 10.10.0.0/27, 10.20.0.0/27
6. Alerts: Trinity ships 3 opt-in rules; script 04 enables by setting parameter
7. Tank's scope: scripts 02 + 04 bind ME to App Insights and enable connector telemetry

**Verification:** Relative links confirmed; Mermaid syntax valid; no broken links detected.

**Reusable skill candidate:** "Private endpoint monitoring operator guide" (structure: operator questions → KQL queries → decision tree → cost note) — portable to Cosmos DB, Event Hubs, etc.

### 🟢 Documentation Freshness Audit (Niobe)

**Date:** 2026-05-20T14:40:24-05:00

Full audit of 13 active markdown files (README.md + docs/**/*.md) verifying sync with infrastructure changes:

**Audit results:**
| Check | Status |
|---|---|
| Region narrative (westus3 → eastus) | ✅ PASS |
| ACL/bypass (None not AzureServices) | ✅ PASS |
| Validation/demo flow alignment | ✅ PASS |
| Module version pin (0.17.0) | ⚠️ FIXED |
| Prereqs (az 2.60+, pwsh 7+, LF) | ✅ PASS |
| Connector test sections | ✅ PASS |
| Architecture diagram (no hard-codes) | ✅ PASS |
| Link integrity (0 broken) | ✅ PASS |
| Contents/TOC drift | ✅ PASS |
| Microsoft Learn citations | ✅ PASS |

**Changes applied:**
1. `docs/managed-environment-setup.md` (line 89) — Explicit version 0.17.0 + re-run safety note
2. `docs/deployment-guide.md` (lines 93–98) — Auto-install version + re-run idempotency documented

**Status:** Production-ready; zero outstanding issues.

---

## Lab Deployment State (Neo, 2026-05-20T21:06:15-05:00)

### Deployment Audit Summary

**Subscription:** 43d55e51-58fe-486f-9e2a-ba56b8dd15de (ME-MngEnvMCAP423074-dmauser-1)  
**Resource Group:** `rg-pbinet-dev-eastus` (single RG, hosts both eastus and westus resources)  
**Audit Date:** 2026-05-20T21:06:15-05:00  
**Scope:** READ-ONLY audit against live Azure state. No changes made.

#### Score

- **22 PASS** — VNets, peering, delegation, private endpoints (KV + Blob), DNS zones, monitoring, public-access lockdown all correct
- **7 GAP** — SQL not deployed (capacity issue), ME not linked to policy, enterprise policy health Undetermined, App Insights not bound, connector flows untested
- **2 UNVERIFIED** — KV secret (`demo-secret`), Blob object (`demo/hello.txt`) unverifiable from public (access blocked—correct)
- **1 KNOWN PLATFORM LIMIT** — Private endpoint diagnostic settings NOT supported (Azure platform constraint); PE health monitored via Azure Monitor Metrics blade

#### Key Gaps (Prioritized)

1. **SQL Module Skip** — East US was at capacity during deploy; set `deploySql=true` and redeploy when available, OR fallback to `eastus2`.
2. **ME Linkage** — Enterprise policy `healthStatus: Undetermined` (ME not linked yet). Requires Tank to run `scripts/02-configure-pp-vnet.ps1 -EnvironmentId <id>`.
3. **App Insights Binding** — Included in script 02; will bind ME to Application Insights via REST PATCH once enabled.
4. **Connector Flows** — Blocked on ME linkage. Once linked, smoke test all 4 connectors (KV, SQL, Blob, Custom HTTP).
5. **Demo Artifacts** — Bicep does NOT provision KV secret or Blob content; manual seeding required post-deploy.
6. **PE Diagnostic Gap in Decisions.md** — PE metrics listed as diagnostic target, but platform does NOT support this. Decision doc must be updated to reflect platform limitation.

#### Files Referenced

- Deploy outputs: `.azure/last-deploy-outputs.json`
- Audit history: `.squad/agents/neo/history.md`
- Punch list: See Trinity + Tank + Niobe sections below

---

## Phase 1 Deployment Summary (Trinity, 2026-05-20T17:10:48-05:00)

**Status:** **Succeeded** (with SQL skipped)  
**Resource Group:** `rg-pbinet-dev-eastus`  
**Deployment Name:** `pp-vnet-kv-demo-202605201710`

### Resources Deployed

| Resource | Name |
|---|---|
| Enterprise Policy | `ep-pbinet-dev` |
| VNet East | `vnet-pbinet-dev-east` (10.10.0.0/16, eastus) |
| VNet West | `vnet-pbinet-dev-west` (10.20.0.0/16, westus) |
| Key Vault | `kv-pbinet-dev-k6ozyjreme` |
| Storage Account | `stpbinetdevk6ozyjremes6m` |
| UAMI | `uami-pbinet-dev` |
| Log Analytics Workspace | `law-pbinet-dev-k6ozyjremes6m` |
| Application Insights | `appi-pbinet-dev` (workspace-based, wired to LAW) |
| PE Key Vault | `pep-kv-pbinet-dev` (10.10.1.4) |
| PE Storage | `pep-stg-pbinet-dev` (10.10.1.5) |
| Private DNS zones | `privatelink.vaultcore.azure.net`, `privatelink.blob.core.windows.net`, `privatelink.database.windows.net` (SQL zone exists, no records yet) |
| Action group | `ag-pbinet-dev-observability` |

### IaC Fixes Applied During Deployment

1. **`diagnosticSettings.bicep` — ARM expression escaping** — Removed generic diagnostic module; moved typed settings into each resource module (KV, Storage, SQL, Network) using proper Bicep `scope:` references.
2. **`private-dns.bicep` — Missing VNet link location** — Added `location: 'global'` to all 6 `Microsoft.Network/privateDnsZones/virtualNetworkLinks`.
3. **`private-endpoint.bicep` — Unsupported PE diagnostic settings** — Removed PE diagnostic settings (Azure platform does NOT support `microsoft.network/privateendpoints` diagnostics); PE metrics accessible via Azure Monitor Metrics blade.
4. **RG name mismatch** — Added `resourceGroupNameOverride` param to `main.bicep` and `dev.parameters.json` (fixed: `rg-pbinet-dev` → `rg-pbinet-dev-eastus`).
5. **App Insights not wired** — Added App Insights module call + outputs in `main.bicep`.

### SQL Status — ⚠️ SKIPPED

**Reason:** `RegionDoesNotAllowProvisioning` — East US at capacity.  
**Options:**
- Option A: Retry East US when capacity available; set `deploySql=true` and re-run `scripts/01-deploy.sh`.
- Option B: Fallback to `eastus2` (requires SQL region param override).

**Blocked:** SQL Server, SQL Database, PE-SQL, SQL private DNS A record, SQL diagnostic settings.

### Monitoring

- Log Analytics workspace deployed with 30-day retention.
- Diagnostic settings: KV (AuditEvent + AzurePolicyEvaluationDetails + AllMetrics), Storage blob (StorageRead/Write/Delete + Transaction), VNets (AllMetrics).
- Alerts: opt-in (enableAlerts=false default; action group deployed).

---

## Phase 2 Prep — Enterprise Policy Binding (Tank, 2026-05-20T18:50:00-05:00)

**Status:** **BLOCKED** — Operator must grant Power Platform Administrator Entra role  
**Blocking Error:** `403 EnvironmentAccess — UserMissingRequiredPermission: ManageProtectionKeys`

### Current State

- Enterprise policy `ep-pbinet-dev` fully provisioned (kind=NetworkInjection, both subnets wired).
- Dataverse provisioned in default environment (`org3b450e2b.crm.dynamics.com` — side effect, benign).
- Script fixes completed: EP module v0.17.0 compatibility bugs fixed, `Ensure-AzContext` bridge added, deploy outputs patched with AI fields.
- **ME not yet linked to policy** — all script logic ready, blocked on role assignment.

### Required Operator Action

Tenant Global Administrator (`ms-breakglass@MngEnvMCAP423074.onmicrosoft.com`) must assign **Power Platform Administrator** Entra role to `admin@MngEnvMCAP423074.onmicrosoft.com`.

**Via Entra admin center:**
1. https://entra.microsoft.com → **Roles and administrators** → **Power Platform administrator** → **Add assignments** → add `admin@MngEnvMCAP423074.onmicrosoft.com`

**Via az CLI (breakglass session):**
```powershell
az login --tenant ebf541ac-cacf-4a40-b46e-1accc3810ef8
# sign in as ms-breakglass@...

$templateId = "11648597-926c-4cf3-9c36-bcebb0ba8dcc"
az rest --method POST `
  --url "https://graph.microsoft.com/v1.0/directoryRoles" `
  --body "{`"roleTemplateId`":`"$templateId`"}"

$roleId = (az rest --method GET `
  --url "https://graph.microsoft.com/v1.0/directoryRoles?\`$filter=roleTemplateId eq '$templateId'" `
  -o json | ConvertFrom-Json).value.id

$adminUserId = "7b5e0f11-5e99-4008-a136-9e42428f73e7"
az rest --method POST `
  --url "https://graph.microsoft.com/v1.0/directoryRoles/$roleId/members/\`$ref" `
  --body "{`"@odata.id`":`"https://graph.microsoft.com/v1.0/directoryObjects/$adminUserId`"}"
```

### After Role Assignment

Resume Phase 2:
```powershell
az account set --subscription 43d55e51-58fe-486f-9e2a-ba56b8dd15de 2>$null

# Enterprise policy link
$ppToken = (az account get-access-token --resource 'https://service.powerapps.com/' -o json | ConvertFrom-Json).accessToken
$envId = "Default-ebf541ac-cacf-4a40-b46e-1accc3810ef8"
$systemId = "/regions/unitedstates/providers/Microsoft.PowerPlatform/enterprisePolicies/09c8ad9a-e3f4-4d60-94aa-978562ec65fc"
$body = '{"SystemId":"' + $systemId + '"}'
$resp = Invoke-WebRequest -Uri "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/environments/$envId/enterprisePolicies/NetworkInjection/link?api-version=2019-10-01" `
    -Method POST -Headers @{ Authorization = "Bearer $ppToken"; 'Content-Type' = 'application/json' } -Body $body

# Should return 202 Accepted
Write-Host "Status: $($resp.StatusCode)"
Write-Host "operation-location: $($resp.Headers['operation-location'])"

# Poll operation-location until status=Succeeded
```

### Phase 2 Attempt #2 — Trial Environment Rejection (Tank, 2026-05-20T21:48:40-05:00)

**Status:** **STILL BLOCKED** (same root cause: role assignment missing)  
**New Blocker Discovered:** Initial `EnvironmentId` was Trial type

#### Critical Finding: Environment Type Mismatch

Tank attempted with user-provided `EnvironmentId c5c98bd4-4de7-ef58-81d3-870bbc85f605`. BAP returns:

```
400 InvalidLifecycleOperationRequest: NewNetworkInjection cannot be performed on environment of type Trial
```

**Root cause:** Trial environments are hard-blocked from network injection. Only **Default**, **Production**, **Sandbox**, and **Developer** types support it.

**Verified Correct Environment:**
- `Default-ebf541ac-cacf-4a40-b46e-1accc3810ef8` (type=Default, protected, display="Contoso (default)")
- Dataverse already provisioned → operation code is `SwapNetworkInjection` (not `NewNetworkInjection`)
- Same BAP REST endpoint works for both

#### BAP REST Bypass Confirmed Viable

The `Microsoft.PowerPlatform.EnterprisePolicies` module v0.17.0 cannot work non-interactively with AccessToken-bridged Az contexts. Tank confirmed direct BAP REST is viable:

```powershell
# Step 1: Get BAP token
$token = (az account get-access-token --resource 'https://service.powerapps.com/' --output json | ConvertFrom-Json).accessToken

# Step 2: Get EP systemId (NOT ARM ID)
$epArmId = "/subscriptions/43d55e51-58fe-486f-9e2a-ba56b8dd15de/resourceGroups/rg-pbinet-dev/providers/Microsoft.PowerPlatform/enterprisePolicies/ep-pbinet-dev"
$epSystemId = (az resource show --ids $epArmId --api-version 2020-10-30-preview --query "properties.systemId" -o tsv)
# Result: /regions/unitedstates/providers/Microsoft.PowerPlatform/enterprisePolicies/09c8ad9a-...

# Step 3: POST link
$envId = "Default-ebf541ac-cacf-4a40-b46e-1accc3810ef8"
$body = @{ SystemId = $epSystemId } | ConvertTo-Json -Compress
$response = Invoke-WebRequest `
    -Uri "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/environments/$envId/enterprisePolicies/NetworkInjection/link?api-version=2019-10-01" `
    -Method Post `
    -Headers @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' } `
    -Body $body
# Returns 202 Accepted with operation-location header
```

**Documented in:** `.squad/skills/pp-bap-rest-subnet-injection/SKILL.md` (complete reference with constraints table, async polling, idempotency checks).

#### Remaining Blocker: ManageProtectionKeys Permission

Even with BAP REST, the call still requires `ManageProtectionKeys` permission. User `admin@MngEnvMCAP423074.onmicrosoft.com` (OID: `7b5e0f11-5e99-4008-a136-9e42428f73e7`) must have:
- **Power Platform Administrator** Entra role (tenant-wide), OR
- **System Administrator** Dataverse role (environment-scope)

Currently has only: **Global Reader** (read-only).

**Unblock remains:** Obtain breakglass account credentials; grant Power Platform Administrator role via Entra ID.

---

---

## Phase 2 Validation Summary (Neo, 2026-05-21T04:33:00Z)

### Overall Verdict: ✅ PASS (with deferred items)

All Azure network plumbing checks pass. Two items explicitly deferred per Option B decisions. One script bug requires fix before CI use.

### Pass / Gap / Deferred Counts

| Category | Count |
|---|---|
| ✅ PASS | 20 |
| ⚠️ Expected / Known State | 2 (EP healthStatus, script bug) |
| Deferred — Option B | 1 (SQL all-up) |
| Deferred — manual | 1 (AI → ME) |
| ❌ GAP (blockers) | **0** |

### Key Validation Evidence

**Private Endpoint + DNS A Records Match:**
| Resource | PE NIC IP | DNS A IP | Match |
|---|---|---|---|
| Key Vault | `10.10.1.4` | `10.10.1.4` | ✅ |
| Storage Blob | `10.10.1.5` | `10.10.1.5` | ✅ |

**Public Access Denial (authenticated KV):**
```
ERROR: (Forbidden) Connection is not an approved private link...
Code: ForbiddenByConnection
```

**Enterprise Policy ARM Properties (both VNets linked):**
```json
"networkInjection": {
  "virtualNetworks": [
    { "id": "...vnet-pbinet-dev-east", "subnet": { "name": "snet-pp-delegated" } },
    { "id": "...vnet-pbinet-dev-west", "subnet": { "name": "snet-pp-delegated" } }
  ]
}
```

**20 PASS items:** KV public denial, Storage public denial, PE NIC IPs (KV+Storage), DNS A records (KV+Storage), delegation (East+West), EP references both VNets, DNS zones linked (3 zones × 2 VNets), diagnostic settings (KV+Storage+VNet+LAW), App Insights workspace, public access disabled (KV+Storage).

**2 Deferred items:**
1. **SQL:** Option B deferred (East US capacity)
2. **AI → ME binding:** Manual PPAC step (no BAP API path exists)

### Script Bug Action Items

| Priority | File | Symptom | Fix |
|---|---|---|---|
| P1 | `scripts/03-validate-network.sh` | CRLF line endings + bash brace parse error | `sed -i 's/\r//' ...` + rewrite `probe_sql_public_denial()` |
| P2 | `scripts/03-validate-network.sh` | KV probe expects 403 but gets 401 | Replace curl-based probe with `az keyvault secret list` authenticated call |

### Recommended Next Actions

| Priority | Owner | Action |
|---|---|---|
| P1 | Neo / Trinity | Fix 3 bugs in `scripts/03-validate-network.sh` |
| P2 | Tank | Bind App Insights to Default ME via PPAC |
| P3 | Tank / maker | Run connector smoke tests (KV, Blob, Custom HTTP) |
| P4 | Tank | Verify demo artifacts: `demo-secret`, `demo/hello.txt` exist |
| P5 | Trinity | Deploy SQL when East US capacity available |

---

## Phase 2 Completion Handoff (Niobe, 2026-05-21T23:45:18-05:00)

### Lab Completion Checklist Delivered

**New document:** `docs/lab-completion-checklist.md` (8 sections, 10.7 KB)

**Structure:**
1. Deployment summary table (Phase 1/2 ✅, Phase 3 ⏳, SQL 🔴)
2. Validation results (20 PASS / 0 GAP / 2 deferred)
3. Remaining manual steps:
   - **Step 1:** App Insights binding via PPAC (`admin.powerplatform.microsoft.com → Manage → Data export → App Insights`)
   - **Step 2:** KV connector smoke test + KQL verification
   - **Step 3:** Blob connector smoke test + verification
   - **Step 4:** SQL deferred re-enablement paths
4. Deferred items table
5. Re-run validation instructions
6. Troubleshooting decision tree with cross-links

**Key Features:**
- All resource names resolved from `.azure/last-deploy-outputs.json`
- Exact PPAC click paths
- KQL queries for trace verification in Application Insights
- SQL Option A (eastus2) and Option B (retry eastus) paths

### README.md & Decisions.md Updates

**README.md:**
- Added status section (Phase 1/2 ✅, Phase 3 ⏳, SQL 🔴)
- Added lab completion checklist to docs index

**decisions.md (this file):**
- Corrected PE diagnostic settings table (2026-05-21T23:45:18-05:00)
- **CORRECTION:** Azure platform does NOT support `microsoft.network/privateendpoints` diagnostic settings. PE telemetry available via Azure Monitor Metrics blade only (metric: `PEConnectionsConnected`).

### Documentation Verification

✅ All 14 markdown docs scanned; 0 broken relative links  
✅ `docs/architecture.md` reviewed for drift; no changes required  
✅ All resource names align with deploy outputs  

### Decision Flags

- **Lab readiness:** Phase 1+2 complete; Phase 3 manual steps unblocked and well-documented
- **PE diagnostic correction:** Closes discrepancy between docs and platform reality
- **Handoff clarity:** Lab completion doc provides exact paths and resource names

---

---

## KV Demo Guide — Structure + Live Verification Findings (Tank, 2026-05-21T07:56:48-05:00)

### Summary

Produced a focused, step-by-step Key Vault demo guide for Daniel's presentation. The guide covers negative test → positive test → telemetry evidence.

### Live Azure Verification Findings

| Item | Finding |
|---|---|
| KV name | `kv-pbinet-dev-k6ozyjreme` |
| `publicNetworkAccess` | `Disabled` ✅ |
| `networkAcls.defaultAction` | `Deny` ✅ |
| `demo-secret` exists | ✅ Deployed via Bicep (value: `Hello from private Key Vault`) — cannot confirm via CLI because public access is closed (which is itself the negative test) |
| RBAC: `admin@MngEnvMCAP423074.onmicrosoft.com` on KV | ❌ **No role assignments** — `Key Vault Secrets User` must be granted before Demo Part 2 |

### Decision: Pre-Flight is Required

Daniel **cannot** jump straight to Demo Part 2. He must first run the `az role assignment create` in Pre-flight §c of the demo guide. Without `Key Vault Secrets User`, `AzureKeyVault.GetSecret` will return 403 inside the Power App.

The negative test (Demo Part 1) needs no pre-flight — `az keyvault secret show` from laptop returns `ForbiddenByConnection` immediately and is ready to demo now.

### Demo Doc Structure Rationale

- **Pre-flight §a–d** covers the one-time setup Daniel was missing (RBAC) plus references for App Insights binding if not done yet.
- **Part 1 (negative)** uses the same `az keyvault secret show` that live verification already demonstrated blocks. Zero extra setup needed.
- **Part 2 (positive)** uses Canvas App + Key Vault connector with delegated auth — simplest possible end-user proof.
- **Part 3 (evidence)** provides two KQL queries: App Insights `dependencies` table and `AzureDiagnostics` `SecretGet` with `CallerIPAddress_s` — the latter is the strongest technical proof because it shows the private IP.

### Reusable Pattern Noted

Always run the negative test first and capture the `ForbiddenByConnection` error as a screenshot before granting RBAC or enabling the connector. This ordering makes the "before/after" story clear and prevents accidentally proving the wrong thing if public access ever gets re-enabled.

**File created:** `docs/demos/keyvault-demo.md`  
**Skill created:** `.squad/skills/negative-test-first-demo-pattern/SKILL.md`

---

## KV Demo Guide & Formula Fix (Tank, 2026-05-21T12:46:19-05:00)

### 🟢 KV demo guide structure + live-verification findings

**Date:** 2026-05-21T07:56:48-05:00  
**File created:** `docs/demos/keyvault-demo.md`

Produced a focused, step-by-step Key Vault demo guide for Daniel's presentation. The guide covers negative test → positive test → telemetry evidence.

**Live Azure verification findings:**
| Item | Finding |
|---|---|
| KV name | `kv-pbinet-dev-k6ozyjreme` |
| `publicNetworkAccess` | `Disabled` ✅ |
| `networkAcls.defaultAction` | `Deny` ✅ |
| `demo-secret` exists | ✅ Deployed via Bicep (value: `Hello from private Key Vault`) — cannot confirm via CLI because public access is closed (which is itself the negative test) |
| RBAC: `admin@MngEnvMCAP423074.onmicrosoft.com` on KV | ❌ **No role assignments** — `Key Vault Secrets User` must be granted before Demo Part 2 |

**Decision: pre-flight is required** — Daniel cannot jump straight to Demo Part 2. He must first run the `az role assignment create` in Pre-flight §c of the demo guide. Without `Key Vault Secrets User`, `AzureKeyVault.GetSecret` will return 403 inside the Power App.

**Demo doc structure rationale:**
- **Pre-flight §a–d** covers the one-time setup Daniel was missing (RBAC) plus references for App Insights binding if not done yet.
- **Part 1 (negative)** uses the same `az keyvault secret show` that live verification already demonstrated blocks. Zero extra setup needed.
- **Part 2 (positive)** uses Canvas App + Key Vault connector with delegated auth — simplest possible end-user proof.
- **Part 3 (evidence)** provides two KQL queries: App Insights `dependencies` table and `AzureDiagnostics` `SecretGet` with `CallerIPAddress_s` — the latter is the strongest technical proof because it shows the private IP.

**Reusable pattern noted:** Always run the negative test first and capture the `ForbiddenByConnection` error as a screenshot before granting RBAC or enabling the connector. This ordering makes the "before/after" story clear.

### 🟢 KV connector formula fix — GetSecret signature

**Date:** 2026-05-21T12:46:19-05:00  
**Triggered by:** Daniel's formula showing red underline in Canvas App formula bar

**Root cause:** The original demo doc instructed:
```text
Set(secretValue, AzureKeyVault.GetSecret("kv-pbinet-dev-k6ozyjreme", "demo-secret").value)
```

This is **wrong**. The Azure Key Vault connector's `GetSecret` action takes **one parameter**: `secretName`. The vault is bound at connection-creation time (when you enter `kv-pbinet-dev-k6ozyjreme` in the connection dialog), not at call time. Power Apps cannot resolve a two-argument overload → red underline.

**Reference:** `https://learn.microsoft.com/en-us/connectors/keyvault/` — `GetSecret` Parameters section: only `secretName (True, string)`.

The return type is a `Secret` record with fields `value`, `name`, `version`, `contentType`, `isEnabled`, `createdTime`, `lastUpdatedTime`. Property `.value` (lowercase) is correct.

**Fix:**
```text
Set(secretValue, AzureKeyVault.GetSecret("demo-secret").value)
```

**What was updated:**
- `docs/demos/keyvault-demo.md` — Step 3 now has a callout: "Do this before typing any formula" and explains the vault-name-in-connection pattern. Step 4 formula corrected to single-argument form. Troubleshooting table gained two new rows covering the red-underline symptoms.

**Secondary finding:** The red underline on the entire `AzureKeyVault` namespace (not just the argument count) indicates the connection was not added to the app. Step 3 now explicitly warns: confirm `kv-demo` appears in the Data panel before proceeding to Step 4.

---

## KV Demo RBAC Automation Now Baked Into Deploy Script + Bicep (Niobe, 2026-05-21T14:27:57-05:00)

### Summary

The Key Vault demo (docs/demos/keyvault-demo.md) was failing with HTTP 403 because the demo operator had no `Key Vault Secrets User` role on the vault. The Power Apps Key Vault connector uses per-user OAuth delegation, so every demo operator must hold this role.

**Resolution:** Automation is now baked into the deploy pipeline:

1. **Bicep:** `infra/modules/keyvault.bicep` and `infra/main.bicep` accept a `demoUserPrincipalIds` array parameter that emits role assignments (principalType: User, role: Key Vault Secrets User).
2. **Deploy Script:** `scripts/01-deploy.sh` auto-resolves the signed-in user via `az ad signed-in-user show` and passes the OID to the `demoUserPrincipalIds` parameter. Supports:
   - `--demo-user-oid <oid>` (repeatable for multiple users)
   - `--no-auto-demo-user` (suppress auto-grant)
3. **Documentation:** `docs/demos/keyvault-demo.md` pre-flight §c rewritten as "Automated" with manual fallback for edge cases.

### Outcome

Fresh deployments via `scripts/01-deploy.sh` automatically grant the signed-in user `Key Vault Secrets User` on the demo vault. No post-deploy manual steps required.

**Demo verified working (2026-05-21):** Button press → label displays "Hello from private Key Vault".

### Implication for Team

Connector-specific RBAC requirements (especially per-user OAuth flows) should be:
- **Pre-seeded** at IaC layer (Bicep parameters for demo user OIDs)
- **Auto-granted** in deploy scripts (resolve signed-in user, inject into Bicep)
- **Documented** as "Automated (with manual fallback)" in pre-flight guides

This pattern reduces demo friction and ensures repeatability.

### Files Modified

- `infra/modules/keyvault.bicep` — added `demoUserPrincipalIds` parameter
- `infra/main.bicep` — wired `demoUserPrincipalIds` through to KV module
- `scripts/01-deploy.sh` — auto-resolve and inject `--demo-user-oid`
- `docs/demos/keyvault-demo.md` — pre-flight §c rewritten; "Recent changes" section added with verification callout

---

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction
