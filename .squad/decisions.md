# Squad Decisions

**Last Updated:** 2026-05-20T13:55:18-05:00  
**Source:** Repo review sweep merge of 14 inbox decisions

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

### 🟡 Shared-Resource Location Drift

**Finding:** `infra/main.bicep` defaults shared resources (RG, Key Vault, Storage, SQL) to `westus3`, while VNets stay at `eastus+westus`.

**Owner:** Trinity

**Follow-up:**
- Align `defaultLocation` to paired region, OR
- Codify and justify why shared services live outside paired network regions.

### 🟡 Key Vault and Storage Bypass Settings

**Finding:** `infra/modules/keyvault.bicep` and `infra/modules/storage.bicep` declare `networkAcls.bypass = 'AzureServices'` despite disabling public network access.

**Owner:** Trinity

**Follow-up:**
- Test whether bypass can be removed cleanly.
- If not removable, document exact product requirement.

### 🟢 Bicep Validation

**Status:** `bicep build` and `bicep lint` pass for `infra/main.bicep` and all modules.

**Verified by:** Trinity

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

**Connector verification steps needed:** Neo dropped 4 merge-ready test-step files:
- neo-tests-keyvault.md
- neo-tests-sql.md
- neo-tests-blob.md
- neo-tests-custom-http.md

---

## Directory & Content Decisions

### 🟡 Archive Directory Status (Niobe decision, team input needed)

**Problem:** `archive/` referenced in `.github/copilot-instructions.md` and `README.md` but does NOT exist.

**Mitigation:** Updated `README.md` to plain text: "archive/ (read-only reference, planned)".

**Options:**
1. **Create archive/** with legacy Fabric lab content (aligns with copilot instructions).
2. **Remove archive references** entirely (if legacy lab not relevant).
3. **Update docs** to clarify archive is future enhancement.

**Recommendation:** Option 1 (create archive) aligns with stated intent.

**Awaiting:** Morpheus or Tank to provide legacy content files.

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
