# Private Endpoint Monitoring Operator Guide

**Pattern:** Comprehensive operator documentation for monitoring workload traffic over Azure private endpoints.

## Use cases

- Monitoring Power Platform → Key Vault / SQL / Storage (primary example)
- Monitoring app-to-database traffic (Cosmos DB, PostgreSQL Flexible Server)
- Monitoring event-driven workloads (Event Hubs, Service Bus private endpoints)
- Cross-service private connectivity verification in hub-spoke or multi-tenant architectures

## Structure template

1. **Summary** (2-3 sentences)
   - What gets monitored
   - Why verification matters (private vs. public, denial visibility, DNS health)
   - Scope (which resources, telemetry sources)

2. **What gets logged** (table)
   - Columns: Resource | Diagnostic Category | Retention | Notes
   - Key fields to capture: AuditEvent, security events, metrics, flow logs
   - Note: PE always has metrics-only (no log categories today)

3. **Architecture of the telemetry flow** (Mermaid)
   - Two data streams: application/workload side (App Insights / custom SDK) → shared workspace
   - Resource diagnostics (KV, SQL, Storage, PE, VNet) → shared workspace
   - Single source of truth: Log Analytics workspace for correlation

4. **Key questions and KQL queries** (minimum 6 queries)
   - (a) "Is the workload reaching the backend over the private endpoint?" [Private path verify]
   - (b) "Are there public-endpoint denial attempts?" [Attack visibility]
   - (c) "Who/what accessed which resource?" [Audit trail]
   - (d) "Is the private endpoint healthy?" [Metrics health]
   - (e) "Is DNS resolution working?" [Indirect validation]
   - (f) "Can I correlate workload events with backend logs?" [End-to-end trace]

5. **Dashboards** (short section)
   - Pin 6 queries to Azure Dashboard for continuous monitoring
   - Optional: Workbook template for more narrative + automation

6. **Alerts** (if applicable)
   - List alert rules (e.g., denial spike, availability drop, health degradation)
   - How to enable and configure action groups
   - Recommended thresholds

7. **Troubleshooting flow** (decision tree)
   - Problem statement → (1) run validation script → (2) check logs → (3) check health → (4) verify DNS → (5) escalate
   - Each step has a runnable command or query

8. **Cost note** (1 paragraph)
   - LAW SKU and retention costs
   - Rule of thumb: small workloads = low single-digit $/month
   - Cost controls: retention tuning, daily caps, archive to blob

9. **References** (bullet list)
   - Microsoft Learn pages cited inline
   - Product documentation for each resource
   - Private endpoint overview

## Key KQL query patterns

### Pattern: Private path verification
```kusto
AzureDiagnostics
| where ResourceType == "<resource>"
| where TimeGenerated > ago(24h)
| where CallerIPAddress in ("<private-subnet-1>", "<private-subnet-2>") 
        or CallerIPAddress startswith "10."
| project TimeGenerated, OperationName, CallerIPAddress, ResultType
```

### Pattern: Public denial detection
```kusto
AzureDiagnostics
| where ResourceType == "<resource>"
| where TimeGenerated > ago(24h)
| where ResultType in ("Forbidden", "Denied") or HttpStatusCode in (403, 401)
| where CallerIPAddress !startswith "10."  -- NOT private
| project TimeGenerated, OperationName, CallerIPAddress, ResultType
```

### Pattern: Resource-specific audit
```kusto
AzureDiagnostics
| where ResourceType == "<resource>"
| where TimeGenerated > ago(1h)
| where OperationName == "<specific-op>"
| project TimeGenerated, OperationName, CallerIPAddress, identity_claim_appid_g, ResultType
```

### Pattern: Private endpoint health
```kusto
AzureMetrics
| where ResourceType == "privateEndpoints"
| where TimeGenerated > ago(24h)
| where MetricName in ("PrivateEndpointConnectionStatus", "BytesIn", "BytesOut")
| summarize LatestStatus=max(Average), TotalBytes=sum(Sum) by ResourceId, bin(TimeGenerated, 1h)
```

### Pattern: Cross-layer correlation
```kusto
requests  -- App Insights table
| where timestamp > ago(1h)
| where name contains "<service>" or url contains "<service>"
| project AppTime=timestamp, AppName=name, AppDuration=duration, AppResultCode=resultCode
| join kind=inner (
    AzureDiagnostics
    | where ResourceType == "<resource>"
    | where TimeGenerated > ago(1h)
    | project KVTime=TimeGenerated, KVOp=OperationName, KVStatus=ResultType
)
on $left.AppTime == $right.KVTime
| where abs(datetime_diff('second', AppTime, KVTime)) < 5
```

## Customization checklist

- [ ] Identify which resources to monitor (KV, SQL, Storage, CosmosDB, etc.)
- [ ] List all diagnostic categories for each resource
- [ ] Document private subnet CIDR ranges or identity patterns
- [ ] Define threshold for "denial spike" alert (e.g., 10 in 5 min)
- [ ] Define threshold for "health degraded" (e.g., status < 1)
- [ ] Specify retention policy for compliance or cost
- [ ] Map operator personas: Azure admin, workload owner, security team
- [ ] Test all 6 KQL queries in target Log Analytics workspace
- [ ] Create dashboard or Workbook template
- [ ] Document alert action group setup (email, webhook, Azure Function)

## Examples in this repo

- **Primary example:** `docs/monitoring.md` (Power Platform → Key Vault/SQL/Storage)
- **Connector walkthroughs:** Each of 4 connectors has a "Testing the private path" section with deny probes + DNS checks + link to monitoring guide query (a)

## Why this pattern matters

1. **Verification:** Proves requests are truly using the private path (not accidentally public)
2. **Compliance:** Audit trail shows who accessed what, when, from which identity
3. **Troubleshooting:** KQL queries are faster than clicking through Azure portal
4. **Cost control:** Monitor ingestion to keep Log Analytics bills predictable
5. **Onboarding:** New operators can follow a single doc instead of hunting scattered telemetry pages
