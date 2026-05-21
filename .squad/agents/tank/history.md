# Project Context

- **Owner:** dmauser
- **Project:** powerplat-network-security — Power Platform VNet support lab. Reproduces the supported config where Power Platform (Power Automate / Power Apps /

## Recent Learnings (see history-archive.md for earlier phases)

## Learnings — 2026-05-21T04:19:51Z (Phase 2 run — ME link success)

- **2026-05-21T04:19:51Z** — Default PP environments start with `governanceConfiguration.protectionLevel: "Basic"`. This blocks `NewNetworkInjection` with `400 InvalidLifecycleOperationRequest: NewNetworkInjection cannot be performed on Power Platform environment because of the governance configuration.` The lifecycle ops enforcement shows `NewNetworkInjection` in `disallowedOperations` with reason `GovernanceConfig`. **Fix:** call `Set-AdminPowerAppEnvironmentGovernanceConfiguration -EnvironmentName $envId -UpdatedGovernanceConfiguration @{ protectionLevel = "Standard" }` from `Microsoft.PowerApps.Administration.PowerShell`. This calls `POST .../environments/{envId}/governanceConfiguration?api-version=2021-04-01`. Returns 202; poll until `EnableGovernanceConfiguration` lifecycle op reaches `Succeeded`. Direct PATCH to `scopes/admin/environments` with `protectionLevel: "Standard"` returns 204 but silently makes no change.
- **2026-05-21T04:19:51Z** — After a successful `NewNetworkInjection` lifecycle op, the BAP link endpoint (`POST .../enterprisePolicies/NetworkInjection/link`) remains callable and will execute as `SwapNetworkInjection` (not fail with "already linked"). This means the link call is **fully idempotent**: re-running it simply performs a swap to the same EP, which also succeeds. The GET endpoint (`GET .../enterprisePolicies/NetworkInjection`) returns 404 regardless of link state; use the `lifecycleOperations/{opId}` poll result (`type.id` = `NewNetworkInjection` or `SwapNetworkInjection`, `state.id` = `Succeeded`) as the authoritative confirmation.
- **2026-05-21T04:19:51Z** — `applicationInsightsId` and `applicationInsightsKey` are **NOT valid fields** in `EnvironmentProperties` in the BAP admin REST API on any tested version (2016-11-01 through 2024-05-01). All PATCH attempts return `400 InvalidRequestContent: Could not find member 'applicationInsightsId' on object of type 'EnvironmentProperties'`. The earlier history entry claiming REST PATCH works was incorrect. App Insights binding for a PP Managed Environment appears to be configurable only via the PPAC admin center UI through an undiscovered internal endpoint. Script 02's AI binding section has been updated to skip this step with a clear warning.
- **2026-05-21T04:19:51Z** — ARM `healthStatus` for the enterprise policy resource remains `Undetermined` even after a confirmed successful `NewNetworkInjection: Succeeded` lifecycle op. The transition to `Running` requires PP control plane to establish actual network infrastructure in the delegated subnets and may take extended time or only trigger when ME workloads actively use VNet injection. `Undetermined` is NOT a sign of failure when the BAP lifecycle op shows `Succeeded`.
- **2026-05-21T04:19:51Z** — `NewNetworkInjection` appearing in `lifecycleOperationsEnforcement.allowedOperations` does NOT mean no EP is linked. After a successful `NewNetworkInjection` the field may still appear in `allowedOperations` alongside `SwapNetworkInjection` and `RevertNetworkInjection`. The only reliable linkage indicators are: (a) the lifecycle op history showing a `NewNetworkInjection: Succeeded` op, and (b) re-submitting the link call, which will return 202 and complete as `SwapNetworkInjection: Succeeded` (not as a new `NewNetworkInjection`).
- **2026-05-21T05:10:00Z** — The correct PPAC path for wiring App Insights telemetry to a Managed Environment is **Manage (left nav) → Data export → App Insights tab → New data export** (resource picker flow; no connection string paste needed). The earlier path "Environments → Settings → Product → Features → Application Insights" does NOT exist in current PPAC. Additionally, all sub-resource REST endpoints probed for data export on both `api.bap.microsoft.com` and `api.powerplatform.com` returned 404 — no public REST path was found. Reference: `learn.microsoft.com/power-platform/admin/set-up-export-application-insights`.

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

## Team Update — 2026-05-21T00:00:00Z (Phase 2 Completion Milestone)

**PHASE 2 COMPLETE.** Default ME linked to enterprise policy; network validation 20 PASS / 0 GAP. Tank: ME linkage succeeded with governance prerequisite discovered (Basic → Standard tier); App Insights PPAC path corrected (Manage → Data export → App Insights). Neo: All 24 validation checks executed; 3 script bugs identified + fixes documented. Niobe: Lab completion checklist delivered (10.7 KB) with manual Phase 3 steps; PE diagnostic settings corrected in decisions.md. All decisions merged from inbox; no archiving needed (all entries dated within 30 days). Daniel ready to resume Phase 3: manual App Insights binding via PPAC, connector smoke tests, SQL re-enable when capacity available. See `.squad/log/2026-05-21T00-00-00Z-phase2-completion.md` for session summary.

## Team Update — 2026-05-20T15:50:00-05:00

**Monitoring trio coordination complete.** App Insights (workspace-based) wired to Trinity's LAW; script 02 now binds PP Managed Environment to App Insights via BAP admin REST PATCH (idempotent, workaround for missing cmdlet in v0.17.0). Script 04 enables connector telemetry + prints canonical KQL queries for Niobe's docs/monitoring.md. Zero integration conflicts; all scripts parse-clean. See `.squad/orchestration-log/2026-05-20T15-50-00Z-tank-1.md` and `.squad/skills/pp-app-insights-wiring/SKILL.md` for REST API pattern (reusable for future PP integrations).
