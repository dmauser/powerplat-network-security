# Trinity History Archive (Pre-2026-05-21)

*Entries archived to keep main history.md under 15360 bytes.*

## Learnings — 2026-05-20T13:55 through 2026-05-20T15:36 (Bicep validation + LAW + diagnostics)

- Bicep build + lint validation passing clean on all files
- Windows CRLF line endings in scripts (fix: .gitattributes text eol=lf)
- Region default changed westus3 → eastus (paired-region primary focus)
- AzureServices bypass changed to None (publicNetworkAccess=Disabled makes bypass moot)
- Bicep edit tool requires exact whitespace match (silently fails on indentation mismatch)
- LAW deployment (SKU PerGB2018, 30–730 day retention parameterized)
- Diagnostic settings pattern: use nested ARM deployment for dynamic scope support
- KV log categories: AuditEvent + AzurePolicyEvaluationDetails (+ AllMetrics)
- Alert philosophy: opt-in by default (enableAlerts=false) prevents lab noise
- PE diagnostic settings NOT supported (use Metrics blade instead via PEConnectionsConnected)

## Learnings — 2026-05-20T17:10 through 2026-05-21T01:00 (Phase 1 deploy + NSP IaC)

- First deployment to rg-pbinet-dev-eastus succeeded; 22 resources (SQL skipped — capacity)
- Bicep bugs fixed: double-escape [ → [[; VNet link location=global; PE diagnostics unsupported; SQL capacity constraint; subscription context drift
- App Insights wired (was dead code in main.bicep before this session)
- NSP module structure: nsp.bicep owns perimeter + profile + full diagnostics
- nsp-association.bicep uses existing references; defaults to Learning mode
- Flow logs scoped to resourceGroup('NetworkWatcherRG') with dedicated storage in lab RG
- API versions pinned (NSP 2023-08-01-preview/2023-11-01; flow logs 2024-05-01)
- West VNet flow logs confirmed in IaC (no future changes needed for west)

## Learnings — 2026-05-21 (Part 4 Function App IaC)

- EP1 Elastic Premium required for regional VNet integration to private endpoints (Consumption plan unreliable)
- East funcapp subnet: 10.10.2.0/27 (snet-pp-delegated=10.10.0.0/27, snet-pep=10.10.1.0/27)
- Function MI RBAC: use guid(resource.id) for role assignment names; principalId only known post-deploy
- 6 private endpoints when deployFunctionApp=true (func inbound + blob + file per region)
- Private DNS zones already linked to both VNets; no changes needed
- Parameterized module pattern: regionSuffix param in resource names (east/west variants)
- West funcapp cross-region KV path (demo core): westus func → VNet peering → eastus KV PE
- Output renames: functionAppName → functionAppEastName/West; funcSubnetId → funcSubnetEastId/West

## All Team Updates & Phase Completion

- Phase 1 Azure plane deployed to rg-pbinet-dev-eastus
- Monitoring trio coordination: LAW + diagnostic settings + App Insights + KQL queries synchronized
- Documentation audit (Neo) + KQL queries + troubleshooting guide (Niobe) all cross-linked
- Lab completion checklist delivered (validation 20 PASS / 0 GAP)
- KV demo RBAC automation in IaC (demoUserPrincipalIds parameter)

---

*For full session details, see main history.md (current sessions) or session logs at .squad/log/ and .squad/orchestration-log/.*
