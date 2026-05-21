# Neo History Archive (Summarized)

**Archive Date:** 2026-05-21T16:09:47-05:00  
**Summarized from:** neo/history.md (16479 bytes → 11.6 KB active + 4.8 KB archived)

---

## Phase 1: Validation Review (2026-05-20T13:55:18-05:00)

- Enhanced `scripts/03-validate-network.sh` with Azure-side DNS verification (PE IPs vs A records)
- Tightened negative-path tests (expecting 403, TCP deny, SAS deny)
- Updated `docs/demo-script.md` with dated runnable commands
- Authored connector-specific test steps for Niobe to merge

---

## Phase 2a: Full Lab Audit (2026-05-20T21:06:15-05:00)

**Key findings:**
- SQL deployment skipped (East US capacity); all other resources verified
- Enterprise policy healthStatus=Undetermined (expected, ME not yet linked)
- PE diagnostic settings NOT supported by Azure platform
- KV/Storage public denial confirmed (403 responses)
- Private DNS A records match PE subnet IPs (10.10.1.4 for KV, 10.10.1.5 for Blob)

**Script bugs identified:**
1. CRLF+LF mixed line endings in `03-validate-network.sh` (bash syntax error on Windows)
2. Bash parsing trap: `{` after `)` in PowerShell command inside `$(...)` substitution
3. KV public denial probe: unauthenticated requests return 401 (missing Bearer), not 403

---

## Phase 2b: Post-ME-Link Validation (2026-05-21T04:33:00Z)

- Confirmed ME link via ARM API (EP `networkInjection.virtualNetworks` shows both VNets + snet-pp-delegated)
- All 24 checks PASS (20 PASS / 0 GAP / 4 DEFERRED/INFO)
- Diagnostic settings verified (KV, blob, VNets → LAW)
- App Insights workspace-based, linked to LAW
- Documented gotchas and proof strategies (az keyvault secret list for auth denial proof, flow log latency, NSP log delays)

---

## Phase 3: KQL Validation Queries (2026-05-21T14:49:51-05:00)

- Created `docs/monitoring-kql.md` (12 ready-to-paste Kusto queries)
  - Q1–Q2: Smoke tests (LAW table presence)
  - Q3–Q8: NSP PE traffic capture (priority: Q4 KV PE inbound)
  - Q9–Q12: Flow analytics (VNet flow, egress detection)
  - Combined view (optional join)
- Added `check_nsp_logs()` function to `03-validate-network.sh` with optional `--check-logs` flag (backward-compatible)
- Documented NSP latency (5–15 min) and flow log delay (10-min window)
- Validated Kusto syntax (standard, no workspace name required in KQL queries)

---

## Patterns Extracted

1. **Validation evidence hierarchy:** Azure-side probes (resource IPs, DNS A records, ARM API state) are most reliable for infrastructure validation.
2. **Negative-path proof:** Use authenticated operation (e.g., `az keyvault secret list`) against public endpoint to get 403 ForbiddenByConnection (stronger than unauthenticated 401).
3. **Log latency expectations:** NSP logs 5–15 min, flow logs 10-min window. Document in operator guides to prevent false-negative alerts.
4. **Query naming convention:** NSP queries Q1–Q4 map to architect spec; Q5+ are additions (use Sx for "supplementary" naming to distinguish).
5. **Optional flags pattern:** Use `--flag` for expensive operations (log queries), maintain existing fast path if flag omitted.

---

## Next Steps Queued

- Phase 4: Stress testing (Part 4 docs planned in roadmap)
- Future: Cross-service KQL dashboards (SQL PE, Blob PE, Custom HTTP)
