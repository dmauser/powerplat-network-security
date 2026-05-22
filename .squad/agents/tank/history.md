# Project Context

- **Owner:** dmauser
- **Project:** powerplat-network-security — Power Platform VNet support lab. Reproduces the supported config where Power Platform (Power Automate / Power Apps / connectors) runs inside delegated Azure VNets with private endpoints to KV, SQL, Storage, and NSP audit oversight.

## Recent Learnings (see history-archive.md for Phase 1–2 entries)

## Learnings — 2026-05-21T07:56:48-05:00 (KV demo guide)

- **Live Azure verified:** `kv-pbinet-dev-k6ozyjreme` has `publicNetworkAccess=Disabled` and `networkAcls.defaultAction=Deny`. Attempting `az keyvault secret list` from outside VNet returns `ForbiddenByConnection` — this is Demo Part 1 negative test.
- **RBAC gap found:** `admin@MngEnvMCAP423074.onmicrosoft.com` had zero role assignments on KV scope. Power Apps KV connector uses delegated OAuth — user must hold `Key Vault Secrets User`. Pre-flight RBAC grant mandatory before Demo Part 2.
- **demo-secret confirmed present via Bicep:** `infra/modules/keyvault.bicep` deploys `demo-secret` with value `Hello from private Key Vault`. Static value sufficient for demo.
- **Demo ordering pattern:** Always run negative test (Part 1) and screenshot `ForbiddenByConnection` BEFORE granting RBAC. Preserves before/after story.
- **KQL evidence:** `AzureDiagnostics | where OperationName == "SecretGet" | project CallerIPAddress_s` shows `10.10.x.x` private IP (strongest proof). App Insights `dependencies` table secondary signal.

## Learnings — 2026-05-21T17:10:00-05:00 (Part 4 dual-region function app deploy)

- **Publish approach:** ARM zip deploy (`az functionapp deploy --src-path <zip> --type zip`) uses ARM management plane — does NOT touch Kudu/SCM. Safe when `publicNetworkAccess=Disabled`. Fallback: Run-from-Package via user-delegation SAS.
- **CallerIPAddress ranges:** Architecturally expected: `10.10.2.X` (east snet-funcapp) and `10.20.2.X` (west snet-funcapp). West function reaches east KV via VNet peering → east KV PE. Not live-verified due to MCAP quota constraint.
- **DNS / PE:** Trinity's Bicep already links `privatelink.vaultcore.azure.net` to both VNets. West function resolves KV hostname to east PE IP correctly. All PE DNS zones linked to both VNets.
- **MCAP subscription quota:** Internal MCAP subscriptions may return `InternalSubscriptionIsOverQuotaForSku` with `Total VMs: 0` for ALL App Service Plan SKUs (EP1, S1, P1v2, B1). Subscription-level hard limit. Fix: request quota increase or use Pay-As-You-Go. Added `aspSkuName`/`aspSkuTier` parameters to `funcapp.bicep` for SKU override.
- **Raw REST vs Az.KeyVault:** Chose raw `Invoke-RestMethod` (IMDS token + KV REST API) over `Az.KeyVault` module because: (1) no module load → faster cold start; (2) auto-tracked by App Insights SDK in Functions PowerShell runtime → guaranteed entries in `dependencies` table (closes Part 4 App Insights gap).
- **Zip layout:** `Compress-Archive -Path <folder>\* -DestinationPath <zip>` puts files at root (required layout). Verify with `[System.IO.Compression.ZipFile]::OpenRead($zip).Entries.FullName`.

## Punch List — Part 4 Unblock (2026-05-21T17:10:00-05:00)

1. Request App Service Plan VM quota for `eastus` and `westus` (minimum 2 × EP1 vCPUs, or 2 × S1 Standard vCPUs).
2. Run: `az deployment group create --resource-group rg-pbinet-dev-eastus --template-file infra/deploy-funcapp-only.bicep --parameters aspSkuName=S1 aspSkuTier=Standard`
3. Run: `pwsh scripts/04-deploy-functions.ps1`
4. Verify smoke test output (see `04-deploy-functions.ps1` → `Invoke-SmokeTest`).
5. Copy actual KQL rows into `.squad/decisions/inbox/tank-part4-deploy-verified.md` replacing architectural placeholders.

## Session: 2026-05-21 — Coordinator Planning + Tank Part 4 Scoping

**Task:** Document Part 4 expansion scope (stress testing, performance profiling).

**Part 4 Ownership for Tank:**
- **Script wiring:** Update `scripts/01-deploy.sh` to include Function App deployment (once Trinity delivers `infra/modules/funcapp.bicep`) and surface Function App outputs to `.azure/last-deploy-outputs.json`
- **Smoke test script:** Create `scripts/07-funcapp-stress-test.sh` — scenario runner: load Function App with high-frequency calls, measure latency (p50/p95/p99), capture traffic through NSP logs + flow analytics, produce perf dashboard JSON.
- **Telemetry:** Integrate with `scripts/04-enable-connector-telemetry.ps1` pattern
- **Ownership:** Tank scripts `01-deploy.sh` (wiring) + `07-*` (stress test + perf validation)

**Expected delivery:** Phase 4 (after Part 3 completion + NSP validation)

**Pattern:** Reuse Tank's idempotent script pattern (`.azure/last-deploy-outputs.json` input, helm-like structured output, graceful skip for conditional features).

## Session: 2026-05-22T08:37:49Z — Tank-5 Final Wrap (Single-RG Directive Complete)

**Timestamp:** 2026-05-22T08:37:49-05:00  
**Status:** Completed (session wrap)

**Work (turns 3–5):**
- **Commit 48391b0:** West flow log deployed + migrated to `rg-pbinet-dev-eastus` via `az resource move`
- **Commit faeeab1:** East NetworkWatcher + flow log migrated same way; Bicep symmetry restored
- **Commit 6a029ef:** Gitignore fix removing erroneous `.squad/decisions/inbox/` exclusion; orphaned east handover committed; GitHub issue #1 opened for uniqueString tech debt

**Single-RG Directive Status:** ✅ COMPLETE. All lab resources (networking, observability, PaaS, security, enterprise policy) now in `rg-pbinet-dev-eastus`.

**Platform Constraint Resolved:** Azure enforces one NetworkWatcher per region per subscription. `az resource move` (supported for Network resources) is the workaround. Constraint documented in decisions.md as caveat for future agents.

**Tech Debt (GitHub Issue #1):** `uniqueString(resourceGroup().id)` collision discovered for flow-logs storage when east + west modules scoped to same RG. Live west storage created in NetworkWatcherRG has different name than what Bicep generates now. Recommendation: add `location` to uniqueString seed to ensure regional resources unique deterministically.

**Deliverables:** 
- Orchestration log: `.squad/orchestration-log/2026-05-22T08-37-49Z-tank-5-wrap.md`
- Session log: `.squad/log/2026-05-22T08-37-49Z-session-wrap-single-rg-complete.md`
- Updated: `.squad/decisions/decisions.md` (merged inbox), `.squad/agents/tank/history.md` (appended)
- Inbox cleanup: All 6 files merged, deleted

**Blocked Items:** Part 4 Function App deployment blocked by MCAP subscription `Total VMs: 0` quota. Unblock path: request quota increase or use Pay-As-You-Go subscription (minimum 2 × EP1 or 2 × S1 vCPU in eastus + westus).

**Learning:** When deploying regional resources to single RG for simplified management, ensure uniqueString seeds include region identifier to avoid hash collisions and deterministic resource naming across regions.

**Next steps:** (1) Resolve Part 4 VM quota blocker; (2) Cleanup Issue #1; (3) Re-enable SQL when capacity available; (4) Complete Part 3 connector demos.


## Session: 2026-05-22T08:37:49Z — Tank-5 Final Wrap (Single-RG Directive Complete)

**Timestamp:** 2026-05-22T08:37:49-05:00  
**Status:** Completed (session wrap)

**Work (turns 3–5):**
- **Commit 48391b0:** West flow log deployed + migrated to `rg-pbinet-dev-eastus` via `az resource move`
- **Commit faeeab1:** East NetworkWatcher + flow log migrated same way; Bicep symmetry restored
- **Commit 6a029ef:** Gitignore fix removing erroneous `.squad/decisions/inbox/` exclusion; orphaned east handover committed; GitHub issue #1 opened for uniqueString tech debt

**Single-RG Directive Status:** ✅ COMPLETE. All lab resources (networking, observability, PaaS, security, enterprise policy) now in `rg-pbinet-dev-eastus`.

**Platform Constraint Resolved:** Azure enforces one NetworkWatcher per region per subscription. `az resource move` (supported for Network resources) is the workaround. Constraint documented in decisions.md as a caveat for future agents.

**Tech Debt (GitHub Issue #1):** `uniqueString(resourceGroup().id)` collision discovered for flow-logs storage when east + west modules scoped to same RG. Live west storage created in NetworkWatcherRG (different hash) has different name than what Bicep generates now. Recommendation: add `location` to uniqueString seed (e.g., `uniqueString(resourceGroup().id, location)`) to ensure regional resources have unique names deterministically.

**Deliverables:** 
- Orchestration log: `.squad/orchestration-log/2026-05-22T08-37-49Z-tank-5-wrap.md`
- Session log: `.squad/log/2026-05-22T08-37-49Z-session-wrap-single-rg-complete.md`
- Updated: `.squad/decisions/decisions.md` (merged inbox), `.squad/agents/tank/history.md` (appended)
- Inbox cleanup: All 6 files merged, deleted

**Blocked Items:** Part 4 Function App deployment blocked by MCAP subscription `Total VMs: 0` quota. Unblock path: request quota increase or use Pay-As-You-Go subscription (minimum 2 × EP1 or 2 × S1 vCPU in eastus + westus).

**Learning:** When deploying regional resources (flow logs, storage, function apps) to a single RG for simplified management, ensure uniqueString seeds include region identifier to avoid hash collisions and deterministic resource naming across regions.

**Next steps:** (1) Resolve Part 4 VM quota blocker; (2) Cleanup Issue #1 (add location to uniqueString seed); (3) Re-enable SQL when capacity available; (4) Complete Part 3 connector demos using NSP + flow logs observability.
