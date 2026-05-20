# Squad Decisions

**Last Updated:** 2026-05-20T14:17:03-05:00  
**Source:** Repo review sweep follow-up completion — all 5 outstanding items resolved

## Architecture & Scope

### US Paired-Region Scope (Morpheus decision)

**Scope:** Power Platform US geography requires **eastus + westus** paired-region architecture for:
- VNets and delegated `snet-pp-delegated` subnets (REQUIRED)
- Private DNS zones linked to both VNets (REQUIRED)
- Microsoft.PowerPlatform/enterprisePolicies `kind=NetworkInjection` referencing both delegated subnets (REQUIRED)

**Shared PaaS Placement:** Separate deployment choice; must be documented explicitly when it differs from paired regions.

**Consequences:**
- Architecture docs distinguish required network-pair scope from parameterized shared-resource placement.
- Diagrams avoid hard-coded names; reflect actual IaC choices.
- Validation logic references paired-region requirements explicitly.

---

## Infrastructure Findings (Morpheus, Trinity)

### 🟢 Shared-Resource Location Drift (RESOLVED)

**Finding:** `infra/main.bicep` defaults shared resources to `westus3`, contradicting the `eastus+westus` paired-region narrative.

**Resolution (Trinity):** Changed `defaultLocation` from `westus3` to `eastus`.
- **Rationale:** `westus3` had no documented justification (no quota, feature, or architecture requirement). It was a footgun for operators accepting defaults. Aligning to `eastus` makes the IaC self-documenting and consistent with docs narrative.
- **Files modified:** `infra/main.bicep`, `infra/parameters/dev.parameters.json`, `docs/architecture.md`, `README.md`.
- **Verification:** `az bicep build` and `az bicep lint` both pass clean; `grep -ri "westus3" infra/ docs/ README.md` returns zero matches.

### 🟢 Key Vault and Storage Bypass Settings (RESOLVED)

**Finding:** Both modules declared `networkAcls.bypass = 'AzureServices'` despite `publicNetworkAccess = 'Disabled'`.

**Resolution (Trinity):** Changed `bypass` to `'None'` on both Key Vault and Storage.
- **Rationale:** The `bypass` property is a public-endpoint firewall setting. With public access disabled, the bypass is functionally inert and creates confusion about trusted exception paths that don't actually exist. Setting `'None'` explicitly signals defense-in-depth intent. No Microsoft Learn documentation requires `AzureServices` bypass for Power Platform VNet support with public access disabled; all runtime traffic flows through delegated subnet → private endpoint path.
- **Caveat:** If public access is ever re-enabled (e.g., break-glass tooling), this decision must be revisited.
- **Files modified:** `infra/modules/keyvault.bicep`, `infra/modules/storage.bicep`, `docs/security-notes.md` (with inline rationale in modules; updated security doc).
- **Verification:** `az bicep build` and `az bicep lint` both pass clean.

### 🟢 Bicep Validation & Compliance

**Status:** `bicep build` and `bicep lint` pass for all modules after region and bypass fixes.

**Verified by:** Trinity (2026-05-20T14:17:03-05:00)

---

## Validation & Demo Gaps

### 🟡 Validation Script Narrowness

**Finding:** `scripts/03-validate-network.sh` hard-codes resource group `rg-pbinet-dev`, validates only public reachability/DNS, does NOT check:
- Enterprise policy subnet references
- Private DNS zone links to both VNets
- Private endpoint contents

**Docs claim:** Full validation coverage (per `docs/deployment-guide.md`)

**Owners:** Tank + Neo

**Follow-up:**
- Parameterize resource group lookup from `.azure/last-deploy-outputs.json`
- Add explicit checks for enterprise policy, DNS zones, private endpoints.

### 🟡 Demo Artifact Provisioning

**Finding:** Bicep creates Key Vault secrets, but NOT SQL objects (`dbo.Sales`) or blob content (`demo/hello.txt`).

**Docs assume:** These artifacts pre-exist.

**Owners:** Tank + Niobe

**Follow-up:**
- Automate prep in post-deploy scripts, OR
- Clearly mark as manual pre-demo preparation.

### 🟢 Network Validation Rewrite (Neo)

**Fixed:**
- Updated `scripts/03-validate-network.sh` to compare Private DNS A records to private endpoint IPs.
- Verify private DNS zone links to both VNets containing `snet-pp-delegated`.
- Expect explicit deny outcomes: Key Vault `403`, SQL TCP 1433 blocked, Blob anonymous `403`, Blob SAS-public `403`.

---

## Documentation Findings (Niobe)

### 🟢 Audit Complete — 100% Compliance

**Scope:** 13 active markdown files (README.md, docs/*, docs/connectors/*)  
**Status:** Production-ready with excellent hygiene.

**Compliance checks (all ✅ PASS):**
- Summary paragraphs + Contents sections + body structure
- Pure GitHub-flavored Markdown (no HTML)
- ATX headings only
- Fenced code blocks with language tags (`bash`, `powershell`, `bicep`, `mermaid`, `text`)
- Placeholder usage (no hard-coded tenant IDs)
- Microsoft Learn inline citations
- Aggressive cross-linking

**Issues found and fixed:**
1. Missing Contents section in README.md — FIXED
2. Broken link to `archive/` — See decision below

**Connector verification steps (MERGED):** Niobe merged Neo's test probes into all 4 connector docs under "## Testing the private path" sections:
- `docs/connectors/keyvault.md` — Added deny/allow probes and private DNS checks
- `docs/connectors/sql.md` — Added deny/allow probes and private DNS checks
- `docs/connectors/blob.md` — Added deny/allow probes and private DNS checks
- `docs/connectors/custom-http.md` — Added deny/allow probes and private DNS checks
- All now follow standardized connector-walkthrough template: summary → contents → overview → before-start → build/create → expected-result → **testing-the-private-path** → notes/troubleshooting → learn-more.

---

## Directory & Content Decisions

### 🟢 Archive Directory Status (RESOLVED)

**Problem:** `archive/` referenced in docs but does NOT exist (zero git history).

**Decision (Niobe):** Option (a) — Remove all archive references.

**Rationale:** 
- No legacy content to preserve (confirmed via `git log --all -- archive/`)
- No future use case documented
- Broken links are a docs hygiene violation
- Clean slate aligns with "active content at repo root" principle

**Action Taken:**
- Removed archive references from `README.md` (removed line + table row)
- Removed archive references from `.github/copilot-instructions.md`
- Result: 0 broken links pointing to archive/ (or any non-existent resource)

### 🟢 Architecture Diagram Cleanup (RESOLVED)

**Finding (Niobe):** `assets/architecture-diagram.mmd` hard-coded resource group name `rg-pbinet-dev`.

**Action Taken:** Replaced with generic placeholder `"Azure subscription"` to align with convention of using deploy-output placeholders instead of hard-coded values.

**Validation:** Mermaid syntax confirmed valid; no broken brackets or flowchart references.

---

## Script & Tooling Updates

### 🟢 Prereqs Script Hardened (Tank)

**Fixed in `scripts/00-prereqs.sh`:**
- Added explicit tool version gates.
- Enforced LF line endings.
- Added `ERR` trap for failure handling.

**Registered providers (Learn-documented PP VNet prereqs):**
- `Microsoft.PowerPlatform`
- `Microsoft.Sql`
- `Microsoft.KeyVault`
- `Microsoft.Storage`
- `Microsoft.Network`
- `enterprisePoliciesPreview` feature flag

**Follow-up:** Decide whether extra infra-only providers (e.g., `Microsoft.ManagedIdentity`) should be registered in `scripts/01-deploy.sh` or documented elsewhere.

### 🟢 PP VNet Link Script Hardened (Tank)

**Fixed in `scripts/02-configure-pp-vnet.ps1`:**
- Pinned `Microsoft.PowerPlatform.EnterprisePolicies` module to v0.17.0.
- Made script re-run safe (same policy = no-op path).
- Added region validation for US geography.

### 🟢 Network Validation Rewritten (Neo)

**Updated `scripts/03-validate-network.sh`:**
- A-record + zone-link verification for private DNS.
- Explicit deny-path checks (Key Vault, SQL, Blob).
- Honest scope statement: bash validator can't test inside delegated subnet; Managed Environment runs required for allow-path proof.

### 🟢 Cleanup Script Fixed (Tank)

**Fixed `scripts/05-cleanup.sh`:**
- Removed hardcoded resource group reference.
- Made deletion targets parameterized.

---

## Doc Sync & Update Decisions

### 🟡 Broader Doc Alignment (Tank finding for Niobe)

**Affected docs:**
- `docs/deployment-guide.md`
- `docs/troubleshooting.md`
- `README.md`

**Decision needed:** Explicitly call out:
1. Version gates in `00-prereqs.sh`
2. `enterprisePoliciesPreview` registration wording for `Microsoft.PowerPlatform/accounts/enterprisePolicies`
3. `02-configure-pp-vnet.ps1` re-run safety when same policy already linked

### 🟡 Provider Registration Ownership (Tank finding for Trinity)

**Scope:** `Microsoft.ManagedIdentity` and other infra-only provider registrations.

**Decision needed:** Should `scripts/01-deploy.sh` self-register these, or should the requirement be documented elsewhere in Trinity's deployment workflow?

---

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction
