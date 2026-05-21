# Project Context

- **Owner:** dmauser
- **Project:** powerplat-network-security — Power Platform VNet support lab
- **Stack:** Bicep, Azure CLI, PowerShell 7, Microsoft.PowerPlatform.EnterprisePolicies module
- **Created:** 2026-05-20

---

## Session: 2026-05-21 (Current)

**Task:** Finalize dual-subnet docs + Part 4 scoping

**Activities:**
- Coordinated with Niobe/Trinity/Tank on architecture docs
- Documented validation query patterns (Q1–Q12 KQL organized by NSP vs flow logs)
- Part 4: Will extend KQL patterns to stress-test telemetry (NSP + flow analytics for latency profiling)

---

## Quick Reference: KQL Query Organization

| Queries | Purpose | Table |
|---------|---------|-------|
| Q1–Q2 | Smoke tests | NSPAccessLogs, AzureNetworkAnalytics_CL |
| Q3–Q8 | NSP PE traffic (priority: Q4 KV inbound) | NSPAccessLogs |
| Q9–Q12 | VNet flow + egress | AzureNetworkAnalytics_CL |

**Key latencies:** NSP 5–15 min, flows 10-min window

---

## Archive

Detailed Phase 1–3 session logs → `history-archive.md`