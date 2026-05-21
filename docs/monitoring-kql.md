# Monitoring KQL queries — NSP audit and flow logs

This guide provides ready-to-paste Kusto Query Language (KQL) queries for validating Network Security Perimeter (NSP) audit-mode capture and Azure VNet flow log capture in Log Analytics. Use these queries to verify that private endpoint traffic is being logged correctly and that Power Platform is reaching backend resources through the private path.

> **Important:** Power Apps and Power Automate connectors run in the **Power Platform service plane**, not in your subscription. Their outbound HTTP/database calls are **NOT visible** to a customer-owned Application Insights instance (`dependencies` table in App Insights only records calls from applications you instrument directly). Use **Log Analytics workspace** queries (NSP and flow logs) instead to validate the private path. For Key Vault connector traffic, see **Query Q4** below.

## Contents

- [Smoke tests (run after deploy)](#smoke-tests-run-after-deploy)
- [Key Vault audit logs (AzureDiagnostics table)](#key-vault-audit-logs-azurediagnostics-table)
- [NSP queries (NSPAccessLogs table)](#nsp-queries-nspaccesslogs-table)
- [Traffic Analytics queries (AzureNetworkAnalytics_CL table)](#traffic-analytics-queries-azurenetworkanalytics_cl-table)
- [Combined view](#combined-view)
- [Log latency note](#log-latency-note)

---

## Smoke tests (run after deploy)

Run these two queries immediately after deploying NSP and enabling flow logs. If they return zero rows, wait 10–15 minutes and retry (see [Log latency note](#log-latency-note) below).

### Query Q1: NSP access logs count (last 1 hour)

Confirms that NSP is logging traffic to the `NSPAccessLogs` table.

```kusto
NSPAccessLogs
| where TimeGenerated > ago(1h)
| count
```

**Expected result:** > 0 rows once Power Platform traffic flows through the private endpoints. Initially may be 0 due to log latency.

### Query Q2: VNet flow log count (last 1 hour)

Confirms that flow logs are arriving in the `AzureNetworkAnalytics_CL` table.

```kusto
AzureNetworkAnalytics_CL
| where TimeGenerated_t > ago(1h)
| count
```

**Expected result:** > 0 rows once any traffic traverses the VNet. You should see flows even from baseline operations.

---

## Key Vault audit logs (AzureDiagnostics table)

These queries provide visibility into Key Vault secret reads captured in the AzureDiagnostics table. Use these to confirm that Power Platform connector calls are reaching your Key Vault through the private path and to verify the caller IP is a private address (not public).

### Query Q3: All Key Vault secret reads (last 1 hour)

Shows every secret read operation from the Key Vault audit logs.

```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.KEYVAULT"
| where TimeGenerated > ago(1h)
| where OperationName == "SecretGet"
| project TimeGenerated, CallerIPAddress, identity_claim_oid_g, requestUri_s, ResultType
| order by TimeGenerated desc
```

**Expected result:** One row per Power Platform connector call (e.g., per Power Apps button click or flow run). `ResultType` should be `Success`. `CallerIPAddress` should be a private IP (10.10.x.x for eastus delegated subnet or 10.20.x.x for westus).

**Latency:** AzureDiagnostics for Key Vault typically arrives in 3–5 minutes.

### Query Q4: Key Vault reads with caller identity detail

Provides caller identity, object ID, request details for auditing.

```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.KEYVAULT"
| where TimeGenerated > ago(1h)
| where OperationName == "SecretGet"
| project TimeGenerated, ResultType, CallerIPAddress, CallerObjectId=identity_claim_oid_g, RequestUri=requestUri_s, HTTPStatusCode=httpStatusCode_d, DurationMs=durationMs_d
| order by TimeGenerated desc
```

**Expected result:** Caller details help correlate with flow execution time and identity. If `CallerIPAddress` is a public IP, the PE/private-DNS path is not being used—see troubleshooting.md.

---

## NSP queries (NSPAccessLogs table)

These queries provide visibility into private endpoint inbound traffic captured by NSP in Learning mode.

### Query Q5: All private endpoint inbound (last 1 hour)

Shows all traffic allowed through private endpoints across all associated resources.

```kusto
NSPAccessLogs
| where TimeGenerated > ago(1h)
| where Category == "NspPrivateInboundAllowed"
| project TimeGenerated, ResourceId, SourceAddress, DestinationPort, Protocol, OperationName
| order by TimeGenerated desc
```

**Expected result:** Traffic originating from Power Platform delegated subnets (10.10.0.0/27 or 10.20.0.0/27) reaching Key Vault, SQL, and Storage private endpoints.

### Query Q6: Private endpoint inbound to Key Vault only (PRIORITY)

Filters NSP logs to show only traffic destined for Key Vault. This is the primary validation query.

```kusto
NSPAccessLogs
| where TimeGenerated > ago(1h)
| where Category == "NspPrivateInboundAllowed"
| where ResourceId contains "Microsoft.KeyVault"
| project TimeGenerated, SourceAddress, DestinationPort, OperationName, ResourceId
| order by TimeGenerated desc
```

**Expected result:** Power Platform connector calls reaching Key Vault private endpoint. SourceAddress should be a private IP (10.x.x.x) from the delegated subnet. DestinationPort should be 443.

### Query Q7: Private endpoint inbound to SQL Server (last 1 hour)

Filters for SQL Server private endpoint traffic.

```kusto
NSPAccessLogs
| where TimeGenerated > ago(1h)
| where Category == "NspPrivateInboundAllowed"
| where ResourceId contains "Microsoft.Sql/servers"
| project TimeGenerated, SourceAddress, DestinationPort, OperationName, ResourceId
| order by TimeGenerated desc
```

**Expected result:** Traffic from delegated subnets to SQL Server PE on port 1433 (or 1438 for named pipes).

### Query Q8: Private endpoint inbound to Storage (last 1 hour)

Filters for Storage Account private endpoint traffic (blob, queue, table, file services).

```kusto
NSPAccessLogs
| where TimeGenerated > ago(1h)
| where Category == "NspPrivateInboundAllowed"
| where ResourceId contains "Microsoft.Storage/storageAccounts"
| project TimeGenerated, SourceAddress, DestinationPort, OperationName, ResourceId
| order by TimeGenerated desc
```

**Expected result:** HTTP/HTTPS traffic from delegated subnets to Storage PE on port 443 and 80 (if HTTP is used).

### Query Q9: Would-be denied in Learning mode (baseline for enforcement)

Shows traffic that would be denied if NSP policy were in Enforced mode. In Learning mode, these are logged but allowed. Use this to establish a baseline before enabling enforcement.

```kusto
NSPAccessLogs
| where TimeGenerated > ago(1h)
| where Category in ("NspPublicInboundPerimeterRulesDenied", "NspPublicInboundResourceRulesDenied")
| project TimeGenerated, ResourceId, SourceAddress, DestinationPort, OperationName, Category
| order by TimeGenerated desc
```

**Expected result:** Empty or near-empty in baseline mode. Any entries here represent traffic that violates the NSP policy you've defined (if any). Useful to review before switching to Enforced mode.

### Query Q10: Top source private IPs touching perimeter resources (last 1 hour)

Ranks the source IPs (should be within delegated subnets) by call volume.

```kusto
NSPAccessLogs
| where TimeGenerated > ago(1h)
| where Category == "NspPrivateInboundAllowed"
| summarize CallCount = count() by SourceAddress, ResourceId
| order by CallCount desc
```

**Expected result:** A handful of private IPs (UAMI, Power Platform runtime IPs) making calls to each resource. High call counts indicate active connector usage.

---

## Traffic Analytics queries (AzureNetworkAnalytics_CL table)

These queries provide visibility into VNet flow data (aggregated flows) and help confirm that Power Platform is using the private path through the delegated subnets.

### Query Q11: Flows originating from delegated subnets (last 1 hour)

Confirms that traffic is flowing from the Power Platform delegated subnets.

```kusto
AzureNetworkAnalytics_CL
| where TimeGenerated_t > ago(1h)
| where SrcSubnet_s in ("10.10.0.0/27", "10.20.0.0/27")
| summarize FlowCount = count() by SrcSubnet_s, DestSubnet_s, DestPort_d
| order by FlowCount desc
```

**Expected result:** Flows from the delegated subnets (10.10.0.0/27 or 10.20.0.0/27) to private endpoint subnets (10.10.1.0/27 or 10.20.1.0/27) on port 443 (HTTPS). This proves Power Platform is using the VNet to reach backends.

### Query Q12: Flows from delegated subnet to private endpoint subnet (last 1 hour)

Confirms that Power Platform is reaching the private endpoint subnet specifically (where KV, SQL, and Storage PEs are located).

```kusto
AzureNetworkAnalytics_CL
| where TimeGenerated_t > ago(1h)
| where SrcSubnet_s in ("10.10.0.0/27", "10.20.0.0/27")
| where DestSubnet_s in ("10.10.1.0/27", "10.20.1.0/27")
| project TimeGenerated_t, SrcSubnet_s, DestSubnet_s, DestPort_d, FlowStatus_s, L7Protocol_s
| order by TimeGenerated_t desc
```

**Expected result:** `FlowStatus_s` should be "A" (allowed). `DestPort_d` should be 443 (HTTPS) for KV/SQL/Storage private endpoints. This confirms the private path is working.

### Query Q13: Top talkers from delegated subnets (last 1 hour)

Ranks the source IPs within delegated subnets by the volume of outbound traffic, helping identify active connectors.

```kusto
AzureNetworkAnalytics_CL
| where TimeGenerated_t > ago(1h)
| where SrcSubnet_s in ("10.10.0.0/27", "10.20.0.0/27")
| summarize BytesSent = sum(SentBytes_d), FlowCount = count() by SrcIP_s
| order by BytesSent desc
```

**Expected result:** A few source IPs (typically UAMI or managed identity IP ranges within the delegated subnet) generating traffic. BytesSent and FlowCount increase with connector activity.

### Query Q14: Flows to public IPs from delegated subnets (egress leakage check, last 1 hour)

Detects any traffic from the delegated subnets to public (non-Azure) IPs. Should be minimal or empty (only expected Azure service IPs).

```kusto
AzureNetworkAnalytics_CL
| where TimeGenerated_t > ago(1h)
| where SrcSubnet_s in ("10.10.0.0/27", "10.20.0.0/27")
| where DestIP_s !startswith "10." and DestIP_s !startswith "172.16." and DestIP_s !startswith "192.168."
| project TimeGenerated_t, SrcIP_s, DestIP_s, DestPort_d, L7Protocol_s, FlowStatus_s
| order by TimeGenerated_t desc
```

**Expected result:** Empty or only known Azure service IPs (e.g., Azure DNS at 168.63.129.16, Azure Storage gateway IPs if using service endpoints). Any unexpected public IPs should be investigated as potential egress leakage.

---

## Combined view

If you want to correlate NSP logs with flow analytics for the same time window, use this join (optional — the two tables capture different layers):

```kusto
let nspLogs = NSPAccessLogs
  | where TimeGenerated > ago(1h)
  | where Category == "NspPrivateInboundAllowed"
  | project nsp_time = TimeGenerated, nsp_resource = ResourceId, nsp_src = SourceAddress, nsp_port = DestinationPort;
let flowLogs = AzureNetworkAnalytics_CL
  | where TimeGenerated_t > ago(1h)
  | where SrcSubnet_s in ("10.10.0.0/27", "10.20.0.0/27")
  | project flow_time = TimeGenerated_t, flow_src = SrcIP_s, flow_dst = DestIP_s, flow_port = DestPort_d;
nspLogs
| join kind=inner (flowLogs) on $left.nsp_src == $right.flow_src
| project nsp_time, nsp_resource, nsp_src, nsp_port, flow_dst, flow_port
```

**Note:** This join is approximate because NSP logs capture the connection-level operation and flow logs capture aggregated flows. The join is best-effort and may produce multiple matches per connection.

---

## Log latency note

**Expected delays:**

- **NSPAccessLogs:** 5–15 minutes after traffic flows. NSP logs are batched and sent asynchronously.
- **AzureNetworkAnalytics_CL (flow logs):** 10-minute processing interval. Flows are aggregated and reported every 10 minutes, so you may not see individual packets, only flow summaries.

**Do not panic if queries return zero rows in the first 10–15 minutes after deployment or a traffic spike.** Retry after 15 minutes. If queries still return zero after 20 minutes, check:

1. **Is traffic actually flowing?** Verify Power Platform is making calls to the backends (e.g., run a test connector action in a Managed Environment flow).
2. **Are diagnostic settings enabled?** Confirm that NSP diagnostic settings and VNet flow logs are linked to the Log Analytics workspace.
3. **Is the workspace in scope?** Verify you are querying the correct workspace (check `<workspaceName>` in the deployment outputs).
4. **Are the tables present?** Run `search "*" | limit 1 | project $table` to list all available tables and confirm `NSPAccessLogs` and `AzureNetworkAnalytics_CL` exist.

---

## References

- [Diagnostic logs for Network Security Perimeter](https://learn.microsoft.com/en-us/azure/private-link/network-security-perimeter-diagnostic-logs)
- [Traffic Analytics overview](https://learn.microsoft.com/en-us/azure/network-watcher/traffic-analytics)
- [Azure Network Analytics reference](https://learn.microsoft.com/en-us/azure/network-watcher/traffic-analytics-schema)
- [NSP concepts](https://learn.microsoft.com/en-us/azure/private-link/network-security-perimeter-concepts)
