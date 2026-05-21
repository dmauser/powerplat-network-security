# Project Context

- **Owner:** dmauser
- **Project:** powerplat-network-security — Power Platform VNet support lab. Reproduces the supported config where Power Platform (Power Automate / Power Apps / Dataverse) reaches private Azure resources (Key Vault, Azure SQL, Storage) via VNet-injected subnets in the US geography (eastus + westus paired regions).
- **Stack:** Bicep (subscription-scope IaC), Azure CLI, PowerShell 7, Microsoft.PowerPlatform.EnterprisePolicies module, Mermaid, GitHub Actions (bicep validate). Active docs at repo root + docs/; legacy Fabric MPE content in archive/ (read-only).
- **Key resources:** 2x VNet w/ snet-pp-delegated + snet-pep, 3x private DNS zones (vaultcore/database/blob) linked to both VNets, Key Vault (publicNetworkAccess=Disabled), Azure SQL serverless, Storage GPv2, UAMI, Microsoft.PowerPlatform/enterprisePolicies kind=NetworkInjection, Managed Environment linked via Enable-SubnetInjection.
- **Created:** 2026-05-20

## Learnings

### 2026-05-20T13:55:18-05:00 — validation review pass

- Replaced operator-box `dig` checks in `scripts/03-validate-network.sh` with stronger Azure-side checks that compare Private DNS A records to private endpoint IPs and verify the zones are linked to both VNets that contain `snet-pp-delegated`.
- Tightened negative-path assertions so the validator now expects explicit denial outcomes: Key Vault public REST `403`, SQL public TCP 1433 denied, Blob anonymous GET `403`, and Blob SAS-over-public `403`.
- Updated `docs/demo-script.md` to separate workstation denial probes from Managed Environment allow-path proofs, with dated runnable commands and connector-specific expected results.
- Connector guides still need richer verification prose, so validator-authored test steps were written to `.squad/decisions/inbox/` for Niobe to merge instead of editing her docs directly.

## Learnings — 2026-05-20T21:06:15-05:00 — Full lab audit (READ-ONLY)

**Trigger:** Daniel requested a complete gap-map against live Azure state.

### What I did
- Listed all resource groups in subscription 43d55e51-58fe-486f-9e2a-ba56b8dd15de.
- Inventoried all resources in `rg-pbinet-dev-eastus`: VNets, subnets, peerings, private endpoints, private DNS zones + VNet links, KV, Storage, enterprise policy, UAMI, LAW, App Insights, action group.
- Checked delegation on both `snet-pp-delegated` subnets.
- Confirmed `publicNetworkAccess=Disabled` + `bypass=None` on KV and Storage.
- Confirmed public-access denial by observing `ForbiddenByConnection` on KV and network-rule block on Storage from operator workstation.
- Verified private DNS A records against PE subnet range (10.10.1.0/27).
- Checked diagnostic settings on KV, Storage blob, VNets, and private endpoints.
- Verified App Insights is workspace-based and connected to LAW.
- Checked enterprise policy healthStatus and both VNet/subnet references.
- Read `.azure/last-deploy-outputs.json` to confirm the SQL skip reason.

### Key findings
1. **SQL is the only missing Azure resource.** East US had no capacity at deploy time. `deploySqlSkipped=true` in deploy outputs. No SQL Server, no SQL Database, no PE SQL, no SQL DNS A record, no SQL diag settings.
2. **Enterprise policy healthStatus = Undetermined.** The policy exists and references both VNets correctly, but `Enable-SubnetInjection` has not been run — no Managed Environment is linked. Script `02-configure-pp-vnet.ps1` has not been executed.
3. **PE diagnostic settings are a platform non-feature.** `microsoft.network/privateendpoints` returns `ResourceTypeNotSupported` for diagnostic settings. The Bicep `private-endpoint.bicep` module already documents this with an inline comment. The decisions.md monitoring table still lists PEs as a diagnostic target — that entry needs correction.
4. **Everything else is solid.** VNets, peering, delegations, private endpoints (KV + blob), all three DNS zones with dual VNet links, KV/Storage public lockdown, diagnostic settings (KV, Storage, VNets), LAW, App Insights — all confirmed correct against expected state.
5. **Public-access denial is verified.** Attempting KV `secret list` from workstation returned `ForbiddenByConnection`; Storage returned a network rule block. These are the correct deny-path outcomes.
6. **Demo artifacts unverifiable from public.** KV secret and blob content can't be listed from operator workstation due to correct private-only access. Status is unverified — Tank should confirm post-ME-link.

### Probe results (Azure-side, no delegated-subnet access)
| Probe | Result | Verdict |
|---|---|---|
| KV public endpoint | `ForbiddenByConnection` | ✅ DENY as expected |
| Storage public endpoint | Network rule block | ✅ DENY as expected |
| DNS A record KV | 10.10.1.4 (in snet-pep) | ✅ PRIVATE |
| DNS A record Blob | 10.10.1.5 (in snet-pep) | ✅ PRIVATE |
| DNS A record SQL | Empty | ❌ SQL not deployed |
| EP healthStatus | Undetermined | ❌ ME not linked |
| PE diag settings | Platform unsupported | ⚠️ KNOWN LIMIT |

### Punch list written
Full gap table and prioritized punch list written to `.squad/decisions/inbox/neo-lab-completion-status-2026-05-20.md`.

## Punch List — Queued for Team (2026-05-20T21:06:15-05:00)

**P1 — Deploy SQL (Trinity):** East US was at capacity during Phase 1. Set `deploySql=true` and re-run `scripts/01-deploy.sh` when available, OR fallback to `eastus2`. This unblocks PE-SQL, DNS A record, and SQL diagnostic settings.

**P2 — Link Managed Environment (Tank):** Run `scripts/02-configure-pp-vnet.ps1 -EnvironmentId <id>` after **operator grants Power Platform Administrator role** to `admin@MngEnvMCAP423074.onmicrosoft.com` (see Phase 2 Prep section in decisions.md). This will set enterprise policy `healthStatus: Running` and bind App Insights to ME.

**P3 — Validate Network (Neo):** After SQL deployed and ME linked, run `scripts/03-validate-network.sh` to verify SQL DNS A record resolution, enterprise policy health, and all three deny-path probes.

**P4 — Verify Demo Artifacts (Tank):** Confirm KV secret (`demo-secret`), Blob object (`demo/hello.txt`), and SQL table (`dbo.Sales`) exist or create manually (Bicep does not provision these).

**P5 — Connector Smoke Tests (maker/Tank demo):** After ME linked and artifacts confirmed, walk through each connector doc (KV, Blob, SQL, Custom HTTP) and execute the smoke test flows.

**P6 — Close PE Diagnostic Gap (Niobe):** Update decisions.md monitoring table to reflect that PE diagnostic settings are NOT supported by Azure (platform limitation); PE metrics are monitored via Azure Monitor Metrics blade instead.

## Team Update — 2026-05-20T19:17:03Z

**Follow-up sweep completed.** Trinity resolved westus3 + AzureServices flags by changing `defaultLocation` to eastus and setting `bypass = 'None'` on Key Vault/Storage modules (see `.squad/orchestration-log/2026-05-20T19-17-03Z-trinity.md`). Niobe merged connector test steps, removed archive references, and cleaned diagram (see `.squad/orchestration-log/2026-05-20T19-17-03Z-niobe.md`). All 5 outstanding items now resolved; decisions merged into `.squad/decisions.md`. See `.squad/log/2026-05-20T19-17-03Z-followup-sweep.md` for round summary.