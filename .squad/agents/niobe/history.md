# Project Context

- **Owner:** dmauser
- **Project:** powerplat-network-security — Power Platform VNet support lab. Reproduces the supported config where Power Platform (Power Automate / Power Apps / Dataverse) reaches private Azure resources (Key Vault, Azure SQL, Storage) via VNet-injected subnets in the US geography (eastus + westus paired regions).
- **Stack:** Bicep (subscription-scope IaC), Azure CLI, PowerShell 7, Microsoft.PowerPlatform.EnterprisePolicies module, Mermaid, GitHub Actions (bicep validate). Active docs at repo root + docs/; legacy Fabric MPE content in archive/ (read-only).
- **Key resources:** 2x VNet w/ snet-pp-delegated + snet-pep, 3x private DNS zones (vaultcore/database/blob) linked to both VNets, Key Vault (publicNetworkAccess=Disabled), Azure SQL serverless, Storage GPv2, UAMI, Microsoft.PowerPlatform/enterprisePolicies kind=NetworkInjection, Managed Environment linked via Enable-SubnetInjection.
- **Created:** 2026-05-20

## Session: 2026-05-20 — Documentation Audit

**Task:** Full audit of active documentation for structure, broken links, HTML, code fences, placeholders, Learn citations, and hard-coded values.

**Scope:** README.md + 12 docs/**/*.md files + 4 connector walkthroughs

**Key Findings:**
- ✅ All 13 files comply with GitHub-flavored Markdown conventions
- ✅ All files have summary paragraphs, contents lists, and proper structure
- ✅ 182 links checked; 1 broken link found and fixed (archive/ reference)
- ✅ All 182 links use correct relative paths
- ✅ No inline HTML detected
- ✅ All code fences properly tagged (bash, powershell, bicep, mermaid, text)
- ✅ All documents use placeholders for deploy outputs (no hard-coded values)
- ✅ Every file includes Microsoft Learn citations for product behavior claims
- ✅ Aggressive cross-linking between docs and connectors

**Actions Taken:**
1. Added `## Contents` section to README.md with proper anchor links
2. Updated archive/ reference from broken link to plain text ("planned")
3. Created decision file: `niobe-archive-directory-status.md` (archive directory doesn't exist; needs team decision)
4. Created comprehensive audit report: `AUDIT-REPORT-2026-05-20.md`

**Conclusion:** Documentation is production-ready. No blocking issues. One structural issue (README.md Contents) fixed. One decision pending (archive directory status).

---

## Learnings

- 2026-05-21T14:27:57-05:00 — **KV demo verified working end-to-end; RBAC automation baked into scripts and Bicep:** Root cause of initial 403: demo operator had no `Key Vault Secrets User` role on the vault (Power Apps connector uses per-user OAuth delegation). Fix delivered: (1) `demoUserPrincipalIds` array parameter added to `infra/modules/keyvault.bicep` and wired through `infra/main.bicep` to emit role assignments (principalType: User); (2) `scripts/01-deploy.sh` auto-resolves signed-in user via `az ad signed-in-user show` and passes OID to Bicep parameter (supports `--demo-user-oid` override and `--no-auto-demo-user` flag); (3) `docs/demos/keyvault-demo.md` pre-flight §c rewritten as "Automated" with manual fallback retained. Demo confirmed: button press → label displays "Hello from private Key Vault" (2026-05-21 verified). Implication: fresh deployments via current scripts require no post-deploy RBAC grant. Pattern: Connector-specific RBAC (per-user OAuth flows) must be pre-seeded at IaC layer with auto-grant in deploy scripts; pre-flight docs as "Automated" with fallback.
- 2026-05-21T23:45:18-05:00 — **Phase 2 completion: lab-completion-checklist.md + PE diagnostic correction:** Created new handoff doc (`docs/lab-completion-checklist.md`, 10.7 KB) with deployment summary, validation results table (20 PASS / 0 GAP / 2 deferred), remaining manual steps for Daniel with exact PPAC click paths for App Insights binding (`admin.powerplatform.microsoft.com → Manage → Data export → App Insights`), KV/Blob connector smoke tests with KQL verification queries, SQL deferred-enablement paths, re-run validation instructions, and troubleshooting decision tree. Updated README.md with status table and lab-completion link. Fixed PE diagnostic settings entry in `.squad/decisions.md` (line 260): corrected table from `AllMetrics` to `Metrics only` + added clarifying note explaining Azure platform constraint (ResourceTypeNotSupported) + cited infra/modules/private-endpoint.bicep + directed to docs/monitoring.md for Metrics blade guidance. Updated README Documentation index to include new checklist. All 14+ markdown docs scanned for broken links; zero failures after refined anchor-aware verification. Pattern: Lab handoff doc structure = status table + validation results + exact manual steps with real resource names from deploy outputs + deferred items table + re-run/troubleshooting pointers + aggressive cross-linking.
- 2026-05-20T15:36:31-05:00 — **docs/monitoring.md authoring complete:** Comprehensive operator guide for monitoring private-endpoint traffic. 10 sections: summary, contents, what-gets-logged (table: Key Vault/SQL/Storage/PE/VNet diagnostic categories), architecture (Mermaid flowchart showing dual data streams: App Insights + resource diagnostics → shared LAW), 6 KQL queries (private-path verification, public denial attempts, secret access audit, PE health, DNS validation, cross-layer correlation), dashboard setup guidance, alerts module with enable/action-group steps, troubleshooting decision tree, cost note with retention/cap guidance, 8 Microsoft Learn references. Placeholder convention used throughout (`<logAnalyticsWorkspaceName>`, `<appInsightsName>`, subnet CIDRs inferred from infra/modules/network.bicep). Cross-links added to: README (docs index), docs/architecture (telemetry plane note), docs/security-notes (logging section expanded), docs/deployment-guide (post-validation link), 4 connector docs (testing-the-private-path sections now reference monitoring queries). Pattern: Operator guide structure = summary + table of what's captured + architecture diagram + operator questions as KQL queries + actionable troubleshooting tree.
- 2026-05-20T14:40:24-05:00 — **Freshness audit after sweep:** All documentation remains accurate after region (eastus), bypass (None), connector test sections, and script version-pin changes. Zero broken links (13 files scanned). Identified stale version-pin documentation (0.17.0 not explicitly documented in deployment-guide; fixed). All 4 connector docs correctly have "Testing the private path" sections. Re-run-safety of 02-configure-pp-vnet.ps1 is now explicitly documented. Pattern: Always verify version pins mentioned in scripts are documented; always note script re-run idempotency.
- 2026-05-20T13:55:18-05:00 — Full repo docs audit passed: all 13 files comply with GitHub-flavored Markdown, summary + contents + body structure, ATX headings, proper code fences with language tags, all 182 links verified, no broken links after fixes.
- 2026-05-20T13:55:18-05:00 — Archive directory is referenced but does NOT exist; requires team decision (create, remove, or clarify as future).
- 2026-05-20T14:17:03-05:00 — Merged Neo's demo-script test steps into all 4 connector docs under "## Testing the private path" sections with public/private deny/allow probe validation patterns.
- 2026-05-20T14:17:03-05:00 — Archive directory decision: git history empty (no commits), removed all 2 archive references from README.md and copilot-instructions.md per option (a).
- 2026-05-20T14:17:03-05:00 — Cleaned up assets/architecture-diagram.mmd: removed hard-coded "rg-pbinet-dev" resource group name, replaced with generic "Azure subscription" placeholder.
- 2026-05-20T14:17:03-05:00 — Connector doc structure now standardized: summary → contents → overview → before-you-start → build/create → expected-result → **testing-the-private-path** → troubleshooting/notes → learn-more. Reusable template emerged.

## Team Update — 2026-05-20T18:55:18Z

**Repo review sweep completed.** All 5 agents delivered findings, fixes, and decisions. See `.squad/decisions.md` for the complete merged decision set. Orchestration logs created at `.squad/orchestration-log/2026-05-20T18-55-18Z-*.md` and team session log at `.squad/log/2026-05-20T18-55-18Z-repo-review-sweep.md`. Your documentation audit passed with 100% compliance after README fixes. Follow-ups pending: archive directory decision, broader doc sync for version gates and re-run safety, connector test-step merge from Neo.

## Team Update — 2026-05-21T00:00:00Z (Phase 2 Completion Milestone)

**PHASE 2 COMPLETE.** Default ME linked to enterprise policy; network validation 20 PASS / 0 GAP. Tank: ME linkage succeeded with governance prerequisite discovered (Basic → Standard tier); App Insights PPAC path corrected (Manage → Data export → App Insights). Neo: All 24 validation checks executed; 3 script bugs identified + fixes committed. Niobe: Lab completion checklist delivered (10.7 KB) with manual Phase 3 steps; PE diagnostic settings corrected in decisions.md. All decisions merged from inbox; no archiving needed (all entries dated within 30 days). Daniel ready to resume Phase 3: manual App Insights binding via PPAC, connector smoke tests, SQL re-enable when capacity available. See `.squad/log/2026-05-21T00-00-00Z-phase2-completion.md` for session summary.

## Team Update — 2026-05-20T15:50:00-05:00

**Monitoring trio coordination complete.** docs/monitoring.md (17.5 KB) delivered with 6 KQL queries, Mermaid telemetry flowchart, and 8-file cross-link refresh (0 broken links). Documentation freshness audit confirmed all changes (region, bypass, script pins, connector tests) are synced and production-ready. Trinity's `logAnalyticsWorkspaceName`/`logAnalyticsWorkspaceId` outputs adopted consistently in docs; Tank's scripts 02+04 referenced explicitly in workflow section. Pattern: Private endpoint monitoring operator guide (structure: operator questions → KQL queries → decision tree → cost note) extracted as reusable skill for future services. See `.squad/orchestration-log/2026-05-20T15-50-00Z-niobe-3.md` for full audit results.

## Punch List — Queued for Niobe (2026-05-20T21:06:15-05:00)

**P6 — Close PE Diagnostic Gap in decisions.md:** Update the monitoring section in `.squad/decisions.md` to reflect the platform limitation discovered during Neo's audit:

Current (incorrect): "PE–KV, PE–SQL, PE–Storage — diagnosticSettings with _(none)_ log categories, `AllMetrics`"

Updated (correct): "Private Endpoint metrics are monitored via Azure Monitor Metrics blade. Azure platform does NOT support `Microsoft.Insights/diagnosticSettings` for `microsoft.network/privateendpoints` (`ResourceTypeNotSupported`). See `infra/modules/private-endpoint.bicep` inline comment for details. Metric used: `PEConnectionsConnected` (active connection count)."

**Rationale:** Neo's audit confirmed this is a known Azure platform limitation. The Bicep module already documents it with inline comments. The decisions.md table must be corrected to close the discrepancy.