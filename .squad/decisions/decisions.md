# Project Decisions — powerplat-network-security

**Last updated:** 2026-05-21T23:26:09-05:00

---

## Project Conventions

### Single-RG Directive (CRITICAL)
- **Date:** 2026-05-21T22:48Z
- **By:** dmauser (via Copilot)
- **Status:** ACTIVE
- **Directive:** Keep ALL lab resources inside `rg-pbinet-dev-eastus`. Avoid creating or scattering resources into other resource groups (e.g., NetworkWatcherRG) when avoidable.
- **Why:** Single-RG layout simplifies cleanup, RBAC, cost tracking, and demo teardown.
- **Caveat for agents:** Some Azure resources are constrained by the platform. Notably, `Microsoft.Network/networkWatchers/flowLogs` is a CHILD of a NetworkWatcher, and the platform-created NetworkWatcher lives in `NetworkWatcherRG` by default. To honor this directive for flow logs specifically, agents must either (a) pre-create a NetworkWatcher in `rg-pbinet-dev-eastus` for the required region(s) and reference it as the parent, or (b) document the exception in this file if the platform forbids it. Same scrutiny applies to private DNS zone groups, peerings, etc. — verify before placing in a non-default RG.

---

## Architecture & Design

### Power Platform Region Selection is Active/Active; Only Deterministic Demo Path is Dual-Region Function Apps
- **Date:** 2026-05-21  
- **Author:** Morpheus (Lead/Network Architect)  
- **Status:** Accepted
- **Summary:** Power Platform's VNet-injected runtime selects between the eastus and westus delegated subnets on a per-call basis (active/active load distribution), not primary/failover. No customer-facing control to pin a connector call to a specific region.
- **Key fact:** Creating multiple Power Apps or multiple Managed Environments in the same geography does NOT guarantee one call per region. Both apps run against the same enterprise policy with the same two delegated subnets; scheduler distributes calls non-deterministically.
- **Only deterministic method:** Deploy the Part 4 Azure Function App with two App Service Plans (one in eastus, one in westus), each VNet-integrated into its own region's delegated workload subnet. Each function's outbound call will provably originate from its own region.
- **Action for Part 4:** Architect as dual-region deployment (eastus + westus ASP). West ASP must be VNet-integrated into `snet-workload` in `vnet-pbinet-dev-west`. West outbound call traverses global VNet peering to reach east-region private endpoints — same path as a west PP worker, but fully under our control.
- **Citations:** [VNet support overview — supported regions](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview#supported-regions); [Set up VNet support for Power Platform](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-setup-configure); Observed lab behavior: `AzureDiagnostics` `CallerIPAddress` alternating between `10.10.0.x` and `10.20.0.x`.

### Part 4 Dual-Region Function App — Implemented
- **Date:** 2026-05-21T16:43:58-05:00  
- **Author:** Trinity (IaC)  
- **Commit:** `ec33957`  
- **Status:** Implemented — pending Tank deployment (blocked by VM quota)
- **Implementation:**
  - Single parameterized `infra/modules/funcapp.bicep` with `regionSuffix` param (`'east'` or `'west'`)
  - Instantiated as `funcAppEast` (location=eastus, regionSuffix=east) and `funcAppWest` (location=westus, regionSuffix=west) in `main.bicep` when `deployFunctionApp=true`
  - Resource names: `func-pbinet-dev-east`, `func-pbinet-dev-west`, `asp-pbinet-dev-east`, `asp-pbinet-dev-west`
  - West function calls EAST Key Vault via global VNet peering (cross-region design)
  - West VNet snet-funcapp subnet: `10.20.2.0/27` (no collision with existing subnets)
  - Six private endpoints deployed (east: sites, blob, file; west: sites, blob, file)
  - VNet integration with `publicNetworkAccess=Disabled` + `vnetRouteAllEnabled=true`
- **Publishing approach:** ARM zip deploy (`az functionapp deploy --type zip`) — uses ARM management plane, not Kudu/SCM; safe with `publicNetworkAccess=Disabled`. Fallback: Run-from-Package via user-delegation SAS on function storage.
- **Expected KQL output (architectural, not yet live-verified):** Key Vault `AzureDiagnostics` shows distinct `CallerIPAddress` values: `10.10.2.X` (east) and `10.20.2.X` (west).
- **Unblock:** Request App Service Plan VM quota (minimum 2 × EP1 or S1 in eastus + westus), or use Pay-As-You-Go subscription.

### Network Security Perimeter (NSP) Audit-Only Spec
- **Date:** 2026-05-21
- **Author:** Morpheus (Lead / Network Architect)
- **Status:** Accepted
- **Topology:** One perimeter in eastus, one profile, three associations.
  - `nsp-pbinet-dev` (location: eastus)
  - `nsp-profile-pbinet-dev`
  - Associations: Key Vault (Learning), SQL Server (Learning), Storage Account (Learning)
- **Access Mode:** Learning (audit-only, non-enforcing). Logs all traffic (allowed/denied) but does NOT enforce restrictions. Existing resource-level network rules remain in effect.
- **Resource Associations:**
  - Key Vault: `Microsoft.KeyVault/vaults` (GA-supported)
  - Azure SQL: `Microsoft.Sql/servers` logical server (GA-supported, covers all databases)
  - Storage: `Microsoft.Storage/storageAccounts` (GA-supported, covers all sub-services)
- **Diagnostic Settings:** Enable ALL NSP log categories (NspPublicInboundPerimeterRulesAllowed, NspPrivateInboundAllowed, etc.) to Log Analytics workspace table `NSPAccessLogs`.
- **Priority order for associations:** Key Vault first, then SQL, then Storage.
- **Citation:** [What is a network security perimeter?](https://learn.microsoft.com/en-us/azure/private-link/network-security-perimeter-concepts); [NSP access modes](https://learn.microsoft.com/en-us/azure/private-link/network-security-perimeter-concepts#access-modes)

### West VNet Flow Logs — VNet-Level Resource Type
- **Date:** 2026-05-21T16:38:49-05:00
- **Author:** Trinity (IaC)
- **Status:** Confirmed (already in main)
- **Decision:** Use `Microsoft.Network/networkWatchers/flowLogs@2024-05-01` (VNet-level), not NSG flow logs.
- **Rationale:** Already the established pattern for east VNet. VNet-level covers all traffic through the VNet in a single resource (simpler than per-NSG). Current recommended approach per Microsoft.
- **Implementation:** Shared `infra/modules/flow-logs.bicep` parameterized by region. Scope: `resourceGroup('NetworkWatcherRG')`. Targets both east and west VNets.

### West Flow Log Migrated to rg-pbinet-dev-eastus (Directive Compliance)
- **Date:** 2026-05-21T18:15:00-05:00
- **Author:** Tank
- **Status:** Completed
- **Action:** West VNet flow log successfully deployed, enabled, and fully inside `rg-pbinet-dev-eastus` per single-RG directive.
- **Platform constraint discovered & resolved:**
  - `az network watcher configure` silently returns existing `NetworkWatcherRG`-hosted watcher (does NOT re-create in different RG)
  - Azure enforces one watcher per region per subscription
  - **Resolution:** `az resource move` supports moving `Microsoft.Network/networkWatchers` between RGs within same subscription; child flow log moved automatically
- **Final placement:**
  - West: `NetworkWatcher_westus` + `fl-vnet-pbinet-dev-west` + `stpbinetfldevwiqxkvrtksy` → ALL in `rg-pbinet-dev-eastus` ✅
  - East: `NetworkWatcher_eastus` + `fl-vnet-pbinet-dev-east` → still in `NetworkWatcherRG` (pending migration with same pattern)
- **Bicep change:** `infra/main.bicep` — `flowLogsStorageWest` and `flowLogWest` scope changed from `resourceGroup('NetworkWatcherRG')` → `rg`. TODO comment added for east migration.

---

## Documentation & Observability

### App Insights Dependencies Do Not Capture Power Platform Connector Traffic
- **Date:** 2026-05-21T15:15:08-05:00  
- **Owner:** Neo (Validator/KQL specialist)  
- **Status:** Documentation corrected; team convention established  
- **Problem:** Key Vault demo guide Part 3 expected App Insights `dependencies` table to show Power Apps KV connector calls. Query always returned zero rows.
- **Root cause:** App Insights only records outbound HTTP calls from applications you instrument directly. Power Apps connectors run in Power Platform service plane (not customer Azure subscription) → their outbound calls NOT visible to customer App Insights.
- **Team convention:** NEVER assume connector dependencies will appear in App Insights. ALWAYS use Log Analytics queries for validation:
  - `AzureDiagnostics` (resource audit logs): OperationName + CallerIPAddress proof
  - `NSPAccessLogs` (NSP Learning mode): private endpoint inbound confirmation
  - `AzureNetworkAnalytics_CL` (VNet flow logs): network-level flow validation
  - Avoid App Insights `dependencies` table for connector validation
  - Document latency expectations: AzureDiagnostics 3–5 min, NSPAccessLogs 5–15 min, VNet flows 10-min windows
- **Implementation:** Updated `docs/demos/keyvault-demo.md` Part 3 — removed misleading App Insights query, added explicit callout, replaced with two working Log Analytics queries. Updated `docs/monitoring-kql.md` with header warning + new "Key Vault audit logs (AzureDiagnostics)" section. Audit scope: zero other misconceptions found.
- **Checklist for future connector docs (SQL, Blob, Custom HTTP):**
  - [ ] Do NOT reference App Insights `dependencies` table
  - [ ] DO use `AzureDiagnostics` queries (OperationName + CallerIPAddress)
  - [ ] DO use `NSPAccessLogs` queries (NspPrivateInboundAllowed + resource filter)
  - [ ] Document latency (3–5 min audit logs, 5–15 min NSP)
  - [ ] Add troubleshooting: "If returns nothing, wait 5 min and retry"
  - [ ] Validate CallerIPAddress / SourceAddress is private (10.x.x.x), not public

### KQL Validation Queries for NSP + Flow Logs
- **Date:** 2026-05-21T14:49:51-05:00  
- **Author:** Neo (Validator)  
- **Status:** Complete — ready for team use  
- **Deliverables:**
  - `docs/monitoring-kql.md` (11.1 KB): 12 ready-to-paste KQL queries organized into smoke tests (Q1–Q2), NSP queries (Q3–Q8), flow analytics (Q9–Q12)
  - Updated `scripts/03-validate-network.sh` with optional `--check-logs` flag
  - `check_nsp_logs()` function runs Q1 (NSP count), Q2 (flow count), Q4 (KV PE inbound count) via `az monitor log-analytics query`
- **Priority query (Q4):** "Private endpoint inbound to Key Vault only" — fastest way to confirm private path working
- **Validator hook:** Optional flag (backward compatible) — operators choose when to run log validation after traffic has flowed 15+ minutes
- **Log latency guidance:** NSP 5–15 min, Flow logs 10-min processing interval
- **Integration points:**
  - Trinity: Verify `logAnalyticsWorkspaceId` export to `.azure/last-deploy-outputs.json`
  - Tank: Test `--check-logs` after NSP deployment + traffic
  - Niobe: Link from `docs/monitoring.md` to new `docs/monitoring-kql.md`

### Comprehensive Power Platform VNet Troubleshooting Guide
- **Date:** 2026-05-21T15:09:22-05:00  
- **Owner:** Niobe (DevRel / Docs)  
- **Status:** Complete  
- **Deliverable:** `docs/troubleshooting.md` (26.6 KB) — comprehensive runtime troubleshooting guide aligned with Microsoft Learn's VNet troubleshooting documentation
- **Structure:**
  - Prerequisites + module setup (PowerShell `Microsoft.PowerPlatform.EnterprisePolicies`)
  - Reference: diagnostic cmdlets table (Get-EnvironmentRegion, Test-DnsResolution, Test-NetworkConnectivity, Test-TLSHandshake, Get-EnvironmentUsage)
  - 6 scenario walkthroughs (MS Learn rewritten with lab resources)
  - Worked example: all 5 cmdlets + real lab resource names + success criteria
  - Bridge to passive monitoring (KQL queries by symptom)
  - When diagnostics fail: non-delegated VM, packet capture, NSP logs
  - Quick reference: old config anti-patterns
- **Lab-specific content:** All examples use real deployment values (subscription, RG, KV FQDN, SQL server, storage, VNet CIDRs, Enterprise Policy)
- **Cross-document updates:** 5 files updated to reference troubleshooting.md (deployment-guide, monitoring, keyvault, architecture, README)
- **Pattern extracted:** Troubleshooting guide structure reusable for future services (SQL PE, Blob PE, etc.)

---

## Infrastructure & IaC

### Function App IaC — funcapp.bicep Module
- **Date:** 2026-05-21
- **Author:** Trinity (Infra Engineer)
- **Status:** Ready for Tank handover
- **Module:** `infra/modules/funcapp.bicep` (resource-group scoped)
- **Resources:**
  - Function storage: `st{prefix}{env}func{uniqueString(rg.id)}` — `publicNetworkAccess=Disabled`, `allowSharedKeyAccess=false`, Standard_LRS
  - App Service Plan: `asp-{prefix}-{env}-func`, EP1 Elastic Premium, Linux
  - Function App: `func-{prefix}-{env}`, PowerShell 7.4, system-assigned MI
  - VNet integration: into `snet-funcapp`, `publicNetworkAccess=Disabled`, `vnetRouteAllEnabled=true`
- **App Settings:** APPLICATIONINSIGHTS_CONNECTION_STRING, KEY_VAULT_NAME, SECRET_NAME, FUNCTIONS_WORKER_RUNTIME=powershell, FUNCTIONS_EXTENSION_VERSION=~4, WEBSITE_RUN_FROM_PACKAGE=1, AzureWebJobsStorage__* (managed identity)
- **RBAC:** Key Vault Secrets User on demo KV, Storage Blob/Account Contributor on function storage
- **Note for Tank:** May need Storage Queue Data Contributor + Storage Table Data Contributor for Functions v4 internal state
- **DNS:** `privatelink.azurewebsites.net` and `privatelink.file.core.windows.net` zones already linked to both VNets
- **Tank's handover checklist:**
  1. Deploy with `deployFunctionApp=true` (default in parameters)
  2. Build PowerShell 7.4 HTTP trigger using KEY_VAULT_NAME + SECRET_NAME via `Az.KeyVault` or raw `Invoke-RestMethod`
  3. Deploy function zip with `az functionapp deployment source config-zip` (safe with publicNetworkAccess=Disabled)
  4. Test from inside VNet; verify App Insights shows KV dependency call
  5. Verify DNS resolution returns 10.10.1.x (snet-pep)

### NSP + Flow Logs Implementation (Bicep)
- **Date:** 2026-05-21
- **Author:** Trinity (IaC)
- **Status:** Implemented
- **Module breakdown:**
  - `infra/modules/nsp.bicep`: Deploys perimeter + profile, attaches all diagnostic log categories to LAW
  - `infra/modules/nsp-association.bicep`: Reusable association child resource; parameters: nspName, profileName, targetResourceId, associationName, accessMode
  - `infra/modules/flow-logs-storage.bicep`: Dedicated `Standard_LRS` StorageV2 account, `publicNetworkAccess=enabled` (for Network Watcher write), 30-day lifecycle policy
  - `infra/modules/flow-logs.bicep`: References existing regional NetworkWatcher, creates VNet flow log child, enables Traffic Analytics (10-min interval) to LAW
- **API versions:** NSP `@2023-08-01-preview` + `@2023-11-01`; Flow logs `@2024-05-01`; Storage `@2023-05-01`
- **Deploy order:** LAW → NSP + profile → VNets → flow-logs storage → east + west flow logs → KV (KV-first association requirement with explicit dependsOn)
- **Main template outputs:** nspName, nspId, flowLogsStorageName

### NSP Prereqs Registration
- **Date:** 2026-05-21
- **Author:** Tank
- **Status:** Complete
- **Changes to `scripts/00-prereqs.sh`:**
  - Added `Microsoft.Network/AllowNSPInPublicPreview` feature registration (required for NSP deployment)
  - Added `Microsoft.Insights` provider registration (NSP diagnostic settings + Traffic Analytics depend on Azure Monitor)
  - `Microsoft.Network` refreshed after NSP feature finishes registering
  - Existing `Microsoft.PowerPlatform/accounts/enterprisePolicies` remains
- **Skipped:** `Microsoft.NetworkAnalytics` — Traffic Analytics is part of `Microsoft.Network` / Network Watcher; Azure auto-provisions `NetworkMonitoring` solution + `AzureNetworkAnalytics_CL` table after first processed flow-log batch
- **Changes to `scripts/01-deploy.sh`:** Surfaces new NSP and flow-log outputs; prints LAW status message with NSPAccessLogs table info

---

## Operations & Deployment

### Power Platform VNet Network Diagnostics Script (06)
- **Date:** 2026-05-21T15:09:22-05:00  
- **Author:** Tank
- **Status:** Merged
- **File:** `scripts/06-network-diagnostics.ps1`
- **Purpose:** Scenario runner wrapping five diagnostic cmdlets into named PASS/FAIL-graded checks against lab's private endpoints (KV, SQL, Storage)
- **Scenarios supported (10 total):**
  - Region, Usage (global checks)
  - KvDns, SqlDns, StorageDns (DNS resolution to private ranges)
  - KvTcp, SqlTcp, StorageTcp (connectivity on 443/1433)
  - KvTls, SqlTls (TLS handshake)
- **Module install:** Pins to v0.17.0 (same as script 02). Pre-seeds globals to avoid Set-StrictMode issues with v0.17.0 module bug.
- **FQDN auto-resolution:** Reads from `.azure/last-deploy-outputs.json` (keyVaultUri, sqlServerFqdn, storageAccountName)
- **Known gaps:**
  1. Diagnostic cmdlet availability in v0.17.0 unverified (script gracefully SKIPs if absent)
  2. SQL scenarios SKIP (east quota exhausted; deploySql=false current state)
  3. DNS IP extraction heuristic (falls back to regex if property names don't match)
  4. `Ensure-AzContext` uses non-approved verb (kept for consistency with script 02; will fix in cleanup pass)

---

## Team Practices

### Idempotent Scripting
- Tank's charter: all shell/PowerShell scripts are re-run-safe and idempotent
- Example: `scripts/00-prereqs.sh` verifies provider/feature registration state, waits only when needed, no duplicate registrations
- Example: `scripts/02-configure-pp-vnet.ps1` re-run-safe for lifecycle ops (same call = same state or idempotent transformation)

### Bicep Linting Standard
- All Bicep files: `az bicep build --file` exit 0 and `az bicep lint --file` exit 0
- Only pre-existing BCP081 on `nsp-association.bicep` (NSP API type not in registry) is acceptable

---

## Status & Dependencies

### Blocked Items

**Part 4 Dual-Region Function App Deployment**
- **Reason:** MCAP internal subscription has Total VMs quota = 0 for all App Service Plan SKUs (EP1, S1, P1v2, B1)
- **Impact:** Cannot live-deploy east + west function apps; cannot verify smoke test output; cannot confirm KQL rows in Key Vault AzureDiagnostics
- **Workaround:** Request quota increase or use Pay-As-You-Go subscription
- **Unblock path:** Once quota available, run `az deployment group create --resource-group rg-pbinet-dev-eastus --template-file infra/deploy-funcapp-only.bicep --parameters aspSkuName=S1 aspSkuTier=Standard`, then `pwsh scripts/04-deploy-functions.ps1`

**East Flow Log Migration to rg-pbinet-dev-eastus**
- **Status:** In-flight (Tank-5 parallel operation)
- **Expected outcome:** NetworkWatcher_eastus + fl-vnet-pbinet-dev-east moved from NetworkWatcherRG to rg-pbinet-dev-eastus
- **Same pattern as west:** `az resource move` to move watcher + flow log

### Deferred Items

**SQL Deployment**
- Current state: deploySql=false (no capacity)
- When capacity available: re-deploy with deploySql=true; SQL diagnostic scripts and NSP associations will auto-activate

**App Insights Binding for Managed Environment**
- Method: PPAC admin center UI (Manage → Data export → App Insights)
- No public REST endpoint found; manual PPAC click-path only
- Documented in `docs/lab-completion-checklist.md` with exact steps

### East Flow Log + Watcher Migration Complete
- **Date:** 2026-05-21
- **Commit:** faeeab1
- **Author:** Tank (infra)
- **Status:** Completed
- **Action:** Migrated `NetworkWatcher_eastus` and child `fl-vnet-pbinet-dev-east` from `NetworkWatcherRG` → `rg-pbinet-dev-eastus` using `az resource move`. Completes single-RG directive: all lab resources now in `rg-pbinet-dev-eastus`.
- **Platform constraint resolved:** Azure enforces one NetworkWatcher per region per subscription; `az network watcher configure` silently returns existing watcher (does NOT re-create in different RG). `az resource move` is the workaround.
- **Bicep change:** `infra/main.bicep` — `flowLogEast` scope changed from `resourceGroup('NetworkWatcherRG')` → `rg`. East and west modules now symmetric.
- **Known drift:** `uniqueString` collision for west storage (both modules scoped to same RG now produce same hash). Live west storage created when scoped to NetworkWatcherRG and has different name than Bicep generates scoped to rg. Future: parameterize west storage name or add location to uniqueString seed.

### East Flow Log Gitignore Correction + Tech Debt Seeding
- **Date:** 2026-05-21
- **Commit:** 6a029ef
- **Author:** Tank (infra)
- **Status:** Completed + GitHub issue #1 opened
- **Action:** Fixed `.gitignore` removing erroneous `.squad/decisions/inbox/` exclusion that blocked east handover from git tracking. Committed orphaned `tank-east-flowlog-migrated.md` into git.
- **Tech debt discovery:** `uniqueString(resourceGroup().id)` seed is identical for east + west flow-logs storage resources when both scoped to `rg-pbinet-dev-eastus`. This causes Bicep to generate the same storage account name for both regions (collision at plan time). The live west storage `stpbinetfldevwiqxkvrtksy` was deployed into NetworkWatcherRG scope (different uniqueString seed) and thus has a different name than what Bicep generates now. A clean re-deploy would create a new storage account and leave the old one orphaned.
- **Opened GitHub issue #1:** "Tech debt: seed uniqueString with location for regional resource uniqueness." Documents the collision and recommends updating `infra/modules/flow-logs-storage.bicep` to include `location` in the uniqueString seed (e.g., `uniqueString(resourceGroup().id, location)`) to ensure east + west storage accounts have unique names deterministically.

---

## Decision Record Index

| Topic | Author | Date | Status |
|-------|--------|------|--------|
| Single-RG Directive | dmauser | 2026-05-21T22:48Z | ACTIVE |
| Region Selection (Active/Active) | Morpheus | 2026-05-21 | Accepted |
| Part 4 Dual-Region Function App | Trinity | 2026-05-21T16:43 | Implemented |
| NSP Audit-Only Spec | Morpheus | 2026-05-21 | Accepted |
| West Flow Logs → rg-pbinet-dev-eastus | Tank | 2026-05-21T18:15 | Completed |
| East Flow Logs → rg-pbinet-dev-eastus | Tank | 2026-05-21 | Completed |
| Gitignore + Issue #1 | Tank | 2026-05-21 | Completed |
| App Insights Dependencies Convention | Neo | 2026-05-21T15:15 | Established |
| KQL Validation Queries | Neo | 2026-05-21T14:49 | Complete |
| Troubleshooting Guide | Niobe | 2026-05-21T15:09 | Complete |
| funcapp.bicep Module | Trinity | 2026-05-21 | Ready |
| NSP + Flow Logs IaC | Trinity | 2026-05-21 | Implemented |
| NSP Prereqs | Tank | 2026-05-21 | Complete |
| Network Diagnostics Script (06) | Tank | 2026-05-21T15:09 | Merged |

---

*Archive decisions older than 30 days to decisions-archive.md when this file exceeds 20,480 bytes. Archive decisions older than 7 days when this file exceeds 51,200 bytes.*
