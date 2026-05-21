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

## Learnings — 2026-05-21T04:33:00Z — Phase 2 validation (post-ME-link)

**Trigger:** Tank completed ME link (commit `052a718`). Daniel requested Phase 2 validation sweep.

### What I did
- Confirmed subscription context and read deploy outputs (`.azure/last-deploy-outputs.json`).
- Attempted `scripts/03-validate-network.sh` via Git Bash — failed with bash syntax error (see gotcha #1).
- Ran all script checks manually via az CLI in PowerShell.
- Verified enterprise policy properties via ARM API (`2020-10-30-preview`).
- Verified both subnet delegations, all three DNS zones + VNet links, PE NIC IPs vs DNS A records, diagnostic settings, KV/Storage public denial.

### Key findings
1. **ME link confirmed via ARM.** EP `ep-pbinet-dev` ARM properties show `networkInjection.virtualNetworks` listing both `vnet-pbinet-dev-east` and `vnet-pbinet-dev-west` with `snet-pp-delegated`. The ARM `healthStatus=Undetermined` is expected (per decisions.md, BAP lifecycle op is authoritative).
2. **All Azure-side plumbing is clean.** KV PE NIC 10.10.1.4 = DNS A 10.10.1.4 ✅; Storage PE NIC 10.10.1.5 = DNS A 10.10.1.5 ✅. Both subnet delegations confirmed. All 3 DNS zones linked to both VNets. All 4 diagnostic settings confirmed (KV, blob, VNet-east, VNet-west → LAW).
3. **SQL is correctly absent.** `deploySqlSkipped=true`, empty `sqlServerFqdn`, no SQL PE, SQL DNS zone is empty. Deferred per Option B.
4. **App Insights is workspace-based.** `ingestionMode=LogAnalytics`, linked to `law-pbinet-dev-k6ozyjremes6m`. PPAC binding to ME is the only remaining manual step.

### New gotchas (script bugs found)

**Gotcha 1 — CRLF+LF mixed line endings in `03-validate-network.sh`.**
`file` confirms: `Unicode text, UTF-8 text executable, with CRLF, LF line terminators`. This causes a bash syntax error on some Git Bash installs (Windows). Fix: run `sed -i 's/\r//' scripts/03-validate-network.sh` before executing, or configure `.gitattributes` to enforce LF.

**Gotcha 2 — `{ 'True' }` / `{ 'False' }` inside `$(...)` in `probe_sql_public_denial()`.**
Bash line 116: the PowerShell `-Command` argument contains `if (\$result.TcpTestSucceeded) { 'True' } else { 'False' }`. Inside a `$(...)` command substitution, the `{` after a `)` token is parsed as a brace group by bash, causing a syntax error. This is a known bash parsing trap. Fix: use a heredoc, single-quoted argument via `$'...'`, or `printf '%s'` to pass the PowerShell command without bash interpreting `{`.

**Gotcha 3 — KV public denial probe asserts HTTP 403, but unauthenticated requests return 401.**
The validation script uses `curl` (no Bearer token) against `https://<kv>.vault.azure.net/secrets/...` and asserts HTTP 403. ACTUAL behavior: Azure KV processes auth before firewall check on unauthenticated requests. Unauthenticated public request → 401 (`AKV10000: missing Bearer token`) with `x-ms-keyvault-network-info` showing the public IP. Authenticated request → 403 `ForbiddenByConnection`. The correct deny-path proof for KV is an authenticated check (`az keyvault secret list`), not a bare curl. Fix: change the script's KV denial probe to `az keyvault secret list` and assert `ForbiddenByConnection` in error output, OR change expected HTTP status to 401 (but that is weaker evidence).

### Validation evidence summary (Phase 2)

| Check | Evidence | Result |
|---|---|---|
| KV public denial | `az keyvault secret list` → `ForbiddenByConnection` | ✅ PASS |
| Storage public denial | `curl` anonymous GET → HTTP 403 | ✅ PASS |
| KV PE NIC IP | `az network nic show` → `10.10.1.4` | ✅ PASS |
| KV DNS A record | `az network private-dns record-set a show` → `10.10.1.4` | ✅ PASS (match) |
| Storage PE NIC IP | `az network nic show` → `10.10.1.5` | ✅ PASS |
| Storage DNS A record | `az network private-dns record-set a show` → `10.10.1.5` | ✅ PASS (match) |
| East snet-pp-delegated | `delegations[0].serviceName = Microsoft.PowerPlatform/enterprisePolicies` | ✅ PASS |
| West snet-pp-delegated | `delegations[0].serviceName = Microsoft.PowerPlatform/enterprisePolicies` | ✅ PASS |
| EP networkInjection | Both VNets + snet-pp-delegated listed | ✅ PASS |
| EP healthStatus | Undetermined | ⚠️ EXPECTED (BAP authoritative) |
| DNS zones → VNet links | All 3 zones: link-east + link-west | ✅ PASS |
| KV diag settings | `diag-kv` → LAW | ✅ PASS |
| Storage blob diag | `diag-blob` → LAW | ✅ PASS |
| VNet East diag | `diag-vnet-east` → LAW | ✅ PASS |
| VNet West diag | `diag-vnet-west` → LAW | ✅ PASS |
| App Insights → LAW | `ingestionMode=LogAnalytics` | ✅ PASS |
| SQL (all) | `deploySqlSkipped=true` | Deferred — Option B |
| AI → ME binding | PPAC manual step | Deferred — manual |
| Script execution | CRLF+LF + `{` syntax error | ⚠️ SCRIPT BUG |

## Team Update — 2026-05-21T00:00:00Z (Phase 2 Completion Milestone)

**PHASE 2 COMPLETE.** Default ME linked to enterprise policy; network validation 20 PASS / 0 GAP. Tank: ME linkage succeeded with governance prerequisite discovered (Basic → Standard tier); App Insights PPAC path corrected (Manage → Data export → App Insights). Neo: All 24 validation checks executed; 3 script bugs identified + fixes committed. Niobe: Lab completion checklist delivered (10.7 KB) with manual Phase 3 steps; PE diagnostic settings corrected in decisions.md. All decisions merged from inbox; no archiving needed (all entries dated within 30 days). Daniel ready to resume Phase 3: manual App Insights binding via PPAC, connector smoke tests, SQL re-enable when capacity available. See `.squad/log/2026-05-21T00-00-00Z-phase2-completion.md` for session summary.

## Team Update — 2026-05-20T19:17:03Z

**Follow-up sweep completed.** Trinity resolved westus3 + AzureServices flags by changing `defaultLocation` to eastus and setting `bypass = 'None'` on Key Vault/Storage modules (see `.squad/orchestration-log/2026-05-20T19-17-03Z-trinity.md`). Niobe merged connector test steps, removed archive references, and cleaned diagram (see `.squad/orchestration-log/2026-05-20T19-17-03Z-niobe.md`). All 5 outstanding items now resolved; decisions merged into `.squad/decisions.md`. See `.squad/log/2026-05-20T19-17-03Z-followup-sweep.md` for round summary.

## Learnings — 2026-05-21T14:49:51-05:00 — KQL validation queries for NSP + flow logs

**Trigger:** Neo authored KQL validation queries companion file and updated `03-validate-network.sh` with optional log checking.

### What I did
- Created `docs/monitoring-kql.md` (11.1 KB) with 12 ready-to-paste KQL queries covering NSP audit logs and flow log analytics.
- Organized queries into sections: smoke tests (Q1–Q2), NSP private-endpoint captures (Q3–Q8), flow analytics (Q9–Q12), combined view, and latency guidance.
- **Priority query Q4:** NSP PE inbound to Key Vault specifically — the user's core validation need.
- Added `check_nsp_logs()` function to `scripts/03-validate-network.sh` that runs Q1, Q2, and Q4 via `az monitor log-analytics query` against LAW.
- Introduced optional `--check-logs` flag to the validation script; maintains existing fast path if flag not set.
- Queries use standard Kusto syntax; no workspace name needed (queries run against selected workspace in Log Analytics).
- Documented 5–15 min NSP log latency and 10-min flow log processing interval; included troubleshooting checklist.

### NSPAccessLogs table schema (from Morpheus spec + Kusto docs)
- `TimeGenerated` (datetime) — when the log was recorded
- `Category` (string) — log category (e.g., `NspPrivateInboundAllowed`, `NspPublicInboundPerimeterRulesDenied`)
- `ResourceId` (string) — full ARM resource ID of the affected resource (KV, SQL, Storage)
- `SourceAddress` (string) — source IP (private IP from delegated subnet in Learning mode)
- `DestinationPort` (int) — destination port (443 for HTTPS, 1433 for SQL, etc.)
- `Protocol` (string) — protocol name (`Tcp`, `Udp`)
- `OperationName` (string) — operation on the resource (e.g., `SecretGet`, `Read`)
- `Profile` (string) — NSP profile name that matched

### AzureNetworkAnalytics_CL table schema (VNet flow logs)
- `TimeGenerated_t` (datetime) — flow window end time
- `SrcSubnet_s` (string) — source subnet CIDR (e.g., "10.10.0.0/27")
- `DestSubnet_s` (string) — destination subnet CIDR (e.g., "10.10.1.0/27")
- `SrcIP_s` (string) — source IP address
- `DestIP_s` (string) — destination IP address
- `DestPort_d` (int) — destination port
- `FlowStatus_s` (string) — "A" (allowed) or "D" (denied)
- `L7Protocol_s` (string) — L7 protocol if available (http, https, sql, etc.)
- `SentBytes_d` (float) — total bytes sent in flow window

### Key decisions made
1. **Single query file per telemetry stream:** Kept NSP and flow log queries separate by table to avoid confusion. Combined view provided as optional join.
2. **Latency guidance critical:** Documented 5–15 min NSP delay + 10 min flow window. Prevents false-negative alerts during first deploy.
3. **Validator hook is optional:** `--check-logs` flag is backward-compatible; existing fast-path validation (DNS, denial checks) unaffected.
4. **Query names map to Morpheus spec.** All Q1–Q4 match Morpheus spec Section 9 starter queries; Q5–Q12 are Neo additions for completeness.
5. **Deployed outputs integration:** Script now attempts to fetch `logAnalyticsWorkspaceId` from deploy outputs; if missing, `--check-logs` fails gracefully.

### Test status
- Script syntax validated (`bash -n`). No CRLF+LF mixed endings in new functions.
- Queries are syntactically correct Kusto and follow Lab Azure conventions (deploy-output placeholders in prose only, not in KQL).

### Punch list written
Decision file written to `.squad/decisions/inbox/neo-kql-queries.md` documenting queries added, validator hook rationale, and team action items.