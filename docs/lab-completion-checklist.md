# Lab Completion Checklist

This document tracks the remaining manual steps to complete the Power Platform VNet support lab. Phases 1 and 2 are deployed and validated; Phase 3 requires manual connector smoke tests in the Power Platform maker portal.

## Contents

- [Deployment summary](#deployment-summary)
- [Validation results](#validation-results)
- [Remaining manual steps](#remaining-manual-steps)
- [Deferred items](#deferred-items)
- [Re-run validation](#re-run-validation)
- [Troubleshooting](#troubleshooting)

## Deployment summary

| Phase | Status | Scope | Evidence |
|-------|--------|-------|----------|
| **Phase 1: Azure Infrastructure** | ✅ Complete | VNets, subnets, peering, private DNS zones, Key Vault, Storage, enterprise policy, managed identity | Commits aaf18f3, da451a8; `.azure/last-deploy-outputs.json` populated |
| **Phase 2: Power Platform Subnet Injection** | ✅ Complete | Managed Environment linked to enterprise policy via `Enable-SubnetInjection`; governance tier upgraded to Standard | Commit 052a718; Default ME `Default-ebf541ac-cacf-4a40-b46e-1accc3810ef8` confirmed linked to `ep-pbinet-dev` |
| **Phase 3: App Insights + Connector Smoke Tests** | ⏳ Pending | Application Insights binding, KV connector test, Blob connector test, SQL deferred | Requires manual PPAC clicks and Power App/flow creation |
| **SQL Service** | 🔴 Deferred | Azure SQL deployment | East US capacity unavailable at deployment time; can be enabled later in alternate region |

---

## Validation results

Neo ran `./scripts/03-validate-network.sh` and confirmed 20 passing checks across enterprise policy, private DNS zones, private endpoints, and network behavior:

| Check Category | Result | Notes |
|---|---|---|
| **Enterprise Policy** | ✅ 20 PASS | Policy exists, references both delegated subnets, correct governance tier |
| **Private DNS Zones** | ✅ All linked | 3 zones (vaultcore, database, blob) linked to both VNets; A records resolve to PE IPs |
| **Private Endpoints** | ✅ All verified | KV, Blob in VNet-East `snet-pep`; public access disabled on all resources |
| **Network Behavior** | ✅ Deny paths confirmed | Public access attempts blocked (403); private paths ready for connector testing |
| **SQL** | 🟡 Deferred | Skipped; capacity to be restored in alternate region |
| **Known Limitations** | 🟡 2 noted | PE diagnostic settings unsupported (Azure platform constraint); validators must use Metrics blade for PE telemetry |

---

## Remaining manual steps

### Step 1: Bind Application Insights for telemetry (PPAC)

Use the Power Platform admin center to connect your Managed Environment to Application Insights. This enables telemetry export so you can verify traffic flows through the private path and trace connector calls.

**Path:**  
`admin.powerplatform.microsoft.com` → **Manage** → **Data export** → **App Insights** tab

**Steps:**

1. Click **New data export**.
2. Name the export (e.g., `ppvnet-dev-export`).
3. Select data types to export: ✅ Dataverse diagnostics, ✅ Power Automate flows, ✅ Canvas app events.
4. Environment: Select `Default-ebf541ac-cacf-4a40-b46e-1accc3810ef8`.
5. Under **Azure details**:
   - Subscription: (choose the subscription where `appi-pbinet-dev` was deployed)
   - Resource group: `rg-pbinet-dev-eastus`
   - Application Insights resource: `appi-pbinet-dev`
6. Click **Create**.

The export begins routing telemetry within a few minutes. The connection string is resolved automatically; you do not need to paste the instrumentation key manually.

**Verification:**  
After ~5 minutes, navigate to `appi-pbinet-dev` in the Azure portal and confirm telemetry tables (e.g., `requests`, `customMetrics`) are populated.

---

### Step 2: Key Vault connector smoke test (Power Apps / Automate)

Create a simple Power Automate flow or Power App in the linked Managed Environment that reads a secret from Key Vault. This proves private endpoint connectivity is working.

**Setup:**

1. Open **make.powerapps.com** and select the environment `Default`.
2. Create a new **Cloud flow** → **Automated** or navigate to **Power Automate** and create a **Scheduled cloud flow**.
3. Add the **Azure Key Vault** action:
   - Vault name: `kv-pbinet-dev-k6ozyjreme`
   - Secret name: `demo-secret`
4. Run the flow manually.

**Expected result:**

- ✅ Flow runs successfully and retrieves the secret value.
- ✅ No public internet connectivity used; traffic flows through the delegated subnet → private endpoint.

**Trace in Application Insights:**

Query the Log Analytics workspace to confirm the request came from the delegated subnet IP:

```kusto
AzureDiagnostics
| where ResourceType == "VAULTS"
| where TimeGenerated > ago(30m)
| where OperationName == "SecretGet"
| project TimeGenerated, CallerIPAddress, ResultType, identity_claim_appid_g
| order by TimeGenerated desc
```

Expected: `CallerIPAddress` starts with `10.10.` (delegated subnet East) or `10.20.` (delegated subnet West).

See [`docs/monitoring.md`](./monitoring.md) for additional KQL queries.

---

### Step 3: Azure Blob Storage connector smoke test (Power Automate)

Create a flow that lists blobs from the Storage account via the private endpoint.

**Setup:**

1. Open **make.powerapps.com** and select environment `Default`.
2. Create a new **Cloud flow** → **Automated** or **Scheduled**.
3. Add the **Azure Blob Storage** action:
   - Storage account name: `stpbinetdevk6ozyjremes6m`
   - Container name: `demo`
   - Action: **List blobs in container**
4. Run the flow manually.

**Expected result:**

- ✅ Flow lists blobs successfully (e.g., any demo blob uploaded to the container).
- ✅ No public connectivity; traffic routes through the private endpoint.

**Verification:**

Check Application Insights or the Storage account diagnostic logs to confirm the request originated from the delegated subnet.

```kusto
AzureDiagnostics
| where ResourceType == "StorageAccounts"
| where TimeGenerated > ago(30m)
| where OperationName == "GetBlob"
| project TimeGenerated, CallerIPAddress, RequestUrl
```

---

### Step 4: SQL connector smoke test (DEFERRED)

Azure SQL Server was not deployed due to East US capacity constraints. To enable SQL testing:

**Option A — Deploy to alternate region (faster):**

```powershell
./scripts/01-deploy.ps1 -DeploySql $true -Location eastus2
```

This redeployment will add SQL Server and Database to the eastus2 region. Redeploy or merge with existing VNet peering as appropriate.

**Option B — Re-run current deployment when capacity is restored:**

```powershell
./scripts/01-deploy.ps1 -DeploySql $true
```

Once SQL is deployed:

1. Create a **SQL Server** connection in Power Automate using the FQDN: `<sqlServerFqdn>` from `.azure/last-deploy-outputs.json`.
2. Use SQL AAD authentication (the environment's managed identity is already set as SQL admin).
3. Query a test table to confirm private endpoint connectivity.

See [`docs/connectors/sql.md`](./connectors/sql.md) for the full walkthrough.

---

## Deferred items

| Item | Reason | How to Enable |
|---|---|---|
| **Azure SQL Database** | East US capacity exhausted at deployment time | Re-run `./scripts/01-deploy.ps1 -DeploySql $true` when capacity is available, or target `eastus2` or `westus`. See step 4 above. |

---

## Re-run validation

To re-run the network validation suite after the lab is complete:

```bash
./scripts/03-validate-network.sh
```

This script verifies:

- Enterprise policy subnet references
- Private DNS zone links to both VNets
- Private endpoint IP resolution
- Public access disabled on all resources
- (Requires Managed Environment to verify allow-path; bash validator cannot test inside delegated subnets)

Expected output: 20 PASS checks (19 if SQL is still deferred).

Troubleshooting: If any check fails, consult [`docs/troubleshooting.md`](./troubleshooting.md) or `.squad/skills/` for domain-specific guidance.

---

## Troubleshooting

### General navigation

- **Bicep/Terraform questions:** See `.squad/skills/` for reusable patterns (e.g., `windows-powershell-pitfalls/SKILL.md`).
- **Power Platform admin center:** See [`docs/managed-environment-setup.md`](./managed-environment-setup.md).
- **Networking:** See [`docs/architecture.md`](./architecture.md) and [`docs/troubleshooting.md`](./troubleshooting.md).
- **Connectors:** See [`docs/connectors/`](./connectors/) for per-connector walkthroughs with private-path validation steps.
- **Monitoring & telemetry:** See [`docs/monitoring.md`](./monitoring.md) for KQL queries and dashboard setup.

### Common issues

**Connector fails with "Cannot reach host":**

1. Confirm the Managed Environment is linked to the enterprise policy (Step 1 above).
2. Verify private DNS zones are linked to both VNets (`docs/troubleshooting.md#dns-resolves-to-a-public-ip-from-inside-azure`).
3. Confirm Network Security Group rules permit outbound traffic from delegated subnets to private endpoint subnet.
4. Run `./scripts/03-validate-network.sh` and review results.

**Application Insights telemetry not appearing:**

1. Confirm the data export was created (step 1 above).
2. Wait 5–10 minutes for telemetry to propagate.
3. Verify the Log Analytics workspace name in `.azure/last-deploy-outputs.json` and query it in the Azure portal.

**Flow throttling or timeouts:**

1. SQL serverless cold-start: first call may take 30+ seconds to wake. Rerun the flow; subsequent calls are faster.
2. Connector connection timeouts: confirm network path by running validation script and checking NSG rules.

---

## Next steps

1. Complete steps 1–3 above (App Insights binding + KV + Blob smoke tests).
2. Run `./scripts/03-validate-network.sh` again to confirm all green.
3. (Optional) Enable SQL in alternate region and run the SQL smoke test (step 4).
4. Review [`docs/demo-script.md`](./demo-script.md) for a guided 20-minute presentation of the lab.
5. Share the lab with stakeholders using the connector walkthroughs in [`docs/connectors/`](./connectors/).

---

## References

- [Architecture overview](./architecture.md)
- [Deployment guide](./deployment-guide.md)
- [Managed Environment setup](./managed-environment-setup.md)
- [Monitoring and telemetry](./monitoring.md)
- [Troubleshooting](./troubleshooting.md)
- [Connector walkthroughs](./connectors/)
- [Virtual Network support for Power Platform (Microsoft Learn)](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview)
