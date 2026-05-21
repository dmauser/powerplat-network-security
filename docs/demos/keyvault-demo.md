# Key Vault demo — VNet-injected Power Platform path

Proves end-to-end that Power Platform reaches a private-only Key Vault (`publicNetworkAccess=Disabled`) through the VNet-injected Managed Environment. Covers a negative test from the public internet, a positive test via Power Apps, and telemetry evidence via App Insights and KV audit logs.

## Contents

- [Pre-flight (one-time setup)](#pre-flight-one-time-setup)
- [Demo Part 1 — Negative test](#demo-part-1--negative-test-proves-public-path-is-blocked)
- [Demo Part 2 — Positive test via Power Apps](#demo-part-2--positive-test-via-power-apps)
- [Demo Part 3 — Evidence the call went through the VNet PE](#demo-part-3--evidence-the-call-went-through-the-vnet-pe)
- [Demo Part 4 — Custom code path with App Insights dependency tracking (planned)](#demo-part-4--custom-code-path-with-app-insights-dependency-tracking-planned)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)

---

## Pre-flight (one-time setup)

### a. Verify KV name and confirm public access disabled

```bash
az account set --subscription 43d55e51-58fe-486f-9e2a-ba56b8dd15de

az keyvault show \
  --name kv-pbinet-dev-k6ozyjreme \
  --query "{name:name, public:properties.publicNetworkAccess, defaultAction:properties.networkAcls.defaultAction}" \
  --output json
```

Expected output:

```text
{
  "defaultAction": "Deny",
  "name": "kv-pbinet-dev-k6ozyjreme",
  "public": "Disabled"
}
```

### b. Confirm demo-secret exists

The secret `demo-secret` (value: `Hello from private Key Vault`) was deployed via Bicep in commit `aaf18f3`. You cannot list or read it from your laptop because the public endpoint is closed — that is by design and is itself Part 1 of the demo.

To replace the value with a timestamp-tagged string (optional):

```bash
az keyvault secret set \
  --vault-name kv-pbinet-dev-k6ozyjreme \
  --name demo-secret \
  --value "hello-from-vnet-$(date -u +%Y%m%dT%H%M%SZ)"
```

> **Note:** This command will also fail from a laptop with no VNet path. Run it from the Azure Cloud Shell (which can reach the vault via the Azure backbone if bypass allows) or accept the static Bicep-deployed value for the demo. The static value is sufficient for the demo.

### c. Grant Daniel `Key Vault Secrets User` role

> **Automated.** `scripts/01-deploy.sh` now auto-grants the signed-in deploy user `Key Vault Secrets User` on the demo vault via the `demoUserPrincipalIds` parameter on `infra/modules/keyvault.bicep`. The Power Apps Key Vault connector uses the signed-in user's delegated identity (OAuth), so the demo operator must hold this role on the vault.
>
> If you ran an earlier version of `01-deploy.sh` (before this automation), or you are demoing with a different user than the one who deployed, add that user's object ID and re-run the deployment:
>
> ```bash
> ./scripts/01-deploy.sh --demo-user-oid <objectId>
> ```
>
> The block below is the manual fallback (use it if you cannot redeploy).

```bash
az role assignment create \
  --assignee "admin@MngEnvMCAP423074.onmicrosoft.com" \
  --role "Key Vault Secrets User" \
  --scope "/subscriptions/43d55e51-58fe-486f-9e2a-ba56b8dd15de/resourceGroups/rg-pbinet-dev-eastus/providers/Microsoft.KeyVault/vaults/kv-pbinet-dev-k6ozyjreme"
```

Verify:

```bash
az role assignment list \
  --assignee "admin@MngEnvMCAP423074.onmicrosoft.com" \
  --scope "/subscriptions/43d55e51-58fe-486f-9e2a-ba56b8dd15de/resourceGroups/rg-pbinet-dev-eastus/providers/Microsoft.KeyVault/vaults/kv-pbinet-dev-k6ozyjreme" \
  --query "[].roleDefinitionName" \
  --output json
```

Expected: `["Key Vault Secrets User"]`

### d. App Insights resource ID (for trace verification)

```text
/subscriptions/43d55e51-58fe-486f-9e2a-ba56b8dd15de/resourceGroups/rg-pbinet-dev-eastus/providers/microsoft.insights/components/appi-pbinet-dev
```

If App Insights telemetry is not yet flowing, bind it first:
`admin.powerplatform.microsoft.com` → **Manage** → **Data export** → **App Insights** tab → **New data export** → select `appi-pbinet-dev`.
See [lab-completion-checklist.md → Step 1](../lab-completion-checklist.md#step-1-bind-application-insights-for-telemetry-ppac).

---

## Demo Part 1 — Negative test (proves public path is blocked)

From Daniel's laptop (outside the VNet), attempt to read the secret directly:

```bash
az keyvault secret show \
  --vault-name kv-pbinet-dev-k6ozyjreme \
  --name demo-secret
```

Expected error:

```text
(Forbidden) Connection is not an approved private link and caller was ignored
because bypass is not set to 'AzureServices' and PublicNetworkAccess is set to 'Disabled'.
Inner error: ForbiddenByConnection
```

This response is the **proof point**: `publicNetworkAccess=Disabled` + `networkAcls.defaultAction=Deny` + `bypass=None` means zero public-internet path. The only way to read this secret is via the private endpoint at `10.10.1.4` inside the VNet.

---

## Demo Part 2 — Positive test via Power Apps

### Step 1 — Open the correct environment

`make.powerapps.com` → top-right env picker → confirm **Default** (`Default-ebf541ac-cacf-4a40-b46e-1accc3810ef8`).

### Step 2 — Create a Canvas App

`make.powerapps.com` → **+ Create** → **Canvas app from blank** → choose **Tablet** → name it `KV VNet Demo`.

### Step 3 — Add the Key Vault connector

> **Do this before typing any formula.** `AzureKeyVault` is only a valid namespace in the formula bar if the connection exists in this app. If you skip this step, every `AzureKeyVault.*` call shows a red underline.

**Data** (left panel) → **+ Add data** → search `Key Vault` → select **Azure Key Vault**.

Connection setup:
- **Sign in** with `admin@MngEnvMCAP423074.onmicrosoft.com`
- **Key vault name**: `kv-pbinet-dev-k6ozyjreme` ← the vault is bound here, NOT in the formula
- Connection display name: `kv-demo`

Click **Connect**. Confirm `kv-demo` appears under **Data** in the left panel before continuing.

### Step 4 — Wire up the UI

> **Formula note:** `GetSecret` takes **one** argument — the secret name only. The vault name is part of the connection (set in Step 3). Passing the vault name as a first argument causes a red underline because no such overload exists.

1. Insert a **Button**. Set `OnSelect`:

```text
Set(secretValue, AzureKeyVault.GetSecret("demo-secret").value)
```

2. Insert a **Label**. Set `Text`:

```text
If(IsBlank(secretValue), "(click button)", secretValue)
```

The `IsBlank` wrapper displays `(click button)` before the first click and shows the secret value after — avoiding a blank label that is indistinguishable from a connector failure. (See Troubleshooting → "Surface the error" for diagnostic techniques.)

See [Appendix — Verified screen YAML](#appendix--verified-screen-yaml) for the full known-good Screen1 definition.

### Step 5 — Save, Play, click the button

- **File** → **Save** → **Play** (▶ top-right).
- Click the button.
- Label should display: `Hello from private Key Vault`

This success — while Part 1 showed `ForbiddenByConnection` — proves the Managed Environment is routing through the delegated subnet → private endpoint `pep-kv-pbinet-dev` (NIC IP `10.10.1.4`).

> **Verified (2026-05-21):** Demo confirmed working end-to-end. The fix path (RBAC automation via `demoUserPrincipalIds` in `infra/modules/keyvault.bicep` and auto-grant in `scripts/01-deploy.sh`) is now baked into fresh deployments — no manual role grant required if you deploy via the current deployment script.

---

## Demo Part 3 — Evidence the call went through the VNet PE

> **IMPORTANT:** The Power Apps Key Vault connector runs in the Power Platform service plane, not in your Azure subscription. Its outbound HTTP calls are **NOT visible to a customer-owned Application Insights instance**. App Insights `dependencies` table only records calls from applications you instrument directly (via SDK or auto-instrumentation). Use **Log Analytics workspace** queries instead to validate the private path.

### Query A: Key Vault audit log (every secret read, ~3–5 min latency)

In the Azure portal: **`law-pbinet-dev-k6ozyjremes6m`** (Log Analytics workspace) → **Logs** → run:

```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.KEYVAULT"
| where TimeGenerated > ago(15m)
| where OperationName == "SecretGet"
| project TimeGenerated, CallerIPAddress, identity_claim_oid_g, requestUri_s, ResultType
| order by TimeGenerated desc
```

**What you'll see:** One row per button press showing `ResultType = Success`.

**Expected `CallerIPAddress`:** A private address from **either** delegated subnet — `10.10.0.0/27` (east) **or** `10.20.0.0/27` (west). Both are valid: Power Platform runs active/active across the paired regions and either worker may originate the call. The west-originated calls traverse the global VNet peering into the east-region private endpoint. See [architecture.md → Why Power Platform needs delegated subnets in BOTH paired regions](../architecture.md#why-power-platform-needs-delegated-subnets-in-both-paired-regions). **If you see a public IP, the PE/private-DNS path is bypassed.** See [troubleshooting.md](../troubleshooting.md) for resolution steps.

**Latency:** AzureDiagnostics for Key Vault typically arrives in 3–5 minutes after the operation.

### Query B: NSP private-endpoint capture (audit-only, ~5–15 min latency)

In the same Log Analytics workspace:

```kusto
NSPAccessLogs
| where TimeGenerated > ago(1h)
| where Category == "NspPrivateInboundAllowed"
| where ResourceId has "kv-pbinet-dev-k6ozyjreme"
| project TimeGenerated, SourceIpAddress, ResourceId, AccessMode=tostring(Properties.accessMode)
| order by TimeGenerated desc
```

**What you'll see:** One row per button press showing the private endpoint inbound traffic. `SourceIpAddress` should be a private address from **either** `10.10.0.0/27` (east delegated subnet) **or** `10.20.0.0/27` (west delegated subnet) — see the [architecture note on dual-region egress](../architecture.md#why-power-platform-needs-delegated-subnets-in-both-paired-regions).

**Latency:** NSP logs can take 5–15 minutes to arrive. Do not panic if this query returns zero rows in the first 10 minutes.

### If Query A returns nothing

1. **Did you click the Power Apps button?** Go back to Demo Part 2 and press the button again to trigger a `SecretGet` operation.
2. **Wait 3–5 minutes** for diagnostic ingestion — AzureDiagnostics has this latency by design.
3. **Confirm KV diagnostic settings target the right LAW.** Run:
   ```bash
   az monitor diagnostic-settings list \
     --resource /subscriptions/43d55e51-58fe-486f-9e2a-ba56b8dd15de/resourceGroups/rg-pbinet-dev-eastus/providers/Microsoft.KeyVault/vaults/kv-pbinet-dev-k6ozyjreme
   ```
   Look for `logs[0].category = "AuditEvent"` and `workspaceId = law-pbinet-dev-k6ozyjremes6m`.
4. **If `CallerIPAddress` is a public IP (not 10.10.x.x):** Private DNS is not resolving. Check that `privatelink.vaultcore.azure.net` private DNS zone is linked to both VNets:
   ```bash
   az network private-dns link vnet list \
     --resource-group rg-pbinet-dev-eastus \
     --zone-name privatelink.vaultcore.azure.net \
     --query "[].virtualNetwork.id" -o tsv
   ```
   Expected: both `vnet-pbinet-dev-east` and `vnet-pbinet-dev-west` resource IDs.

---

## Demo Part 4 — Custom code path with App Insights dependency tracking (planned)

> **Why this part exists.** The Power Apps Key Vault connector runs in the Power Platform service plane and is therefore invisible to a customer-owned Application Insights instance (see the IMPORTANT box at the top of Part 3). To get end-to-end **distributed tracing** — `requests` → `dependencies` to `*.vault.azure.net` — you need code **you instrument**, running on compute **you own**, routed through the **same private endpoint** the connector uses. A small Azure Function App is the lightest way to demonstrate that.
>
> **Status:** scoped. Bicep + deployment wiring not yet merged. Track in [`expansion-roadmap.md`](../expansion-roadmap.md). Owners on the squad: Trinity (Bicep), Tank (deploy + smoke test), Niobe (this doc).

### What this demo will prove

1. The **same Key Vault private endpoint** that serves the Power Apps connector also serves a VNet-integrated Function App — no second PE required.
2. **App Insights dependency tracking lights up** for the custom path. The query that returns zero rows today (`dependencies | where target contains "vault.azure.net"`) will return one row per Function invocation, with `success = true`, `resultCode = 200`, and `target` resolving to a private IP.
3. **End-to-end correlation** works: a single `operation_Id` ties together the HTTP `requests` row (Function entry) and the `dependencies` row (Key Vault call) so you can demo distributed tracing without a second service.

### Target shape

- **Function App (PowerShell 7.4 or .NET 8 isolated)** with one HTTP trigger that calls `Get-AzKeyVaultSecret` (or `SecretClient.GetSecretAsync`) for `demo-secret`.
- **System-assigned managed identity** on the Function App, granted `Key Vault Secrets User` on `kv-pbinet-dev-*`.
- **VNet integration** (regional, outbound) to a new `snet-funcapp` `/27` in `vnet-pbinet-dev-east` — separate from `snet-pp-delegated` (PP owns that delegation) and separate from `snet-pep` (no app workloads in PE subnets).
- **Private DNS** already covers it: `privatelink.vaultcore.azure.net` is linked to both VNets, so the Function's outbound DNS lookup resolves to the private IP automatically.
- **Same App Insights instance** (`appi-pbinet-dev`) so existing dashboards and the `dependencies` KQL just start returning rows.
- **`publicNetworkAccess = Disabled`** on the Function App's inbound surface, with access through a fourth private endpoint on `snet-pep` (so the trigger URL is reachable only from inside the VNet or via a jump host).

### KQL that will start working after Part 4 deploys

```kusto
// Run in: appi-pbinet-dev (Application Insights)
union requests, dependencies
| where timestamp > ago(30m)
| where operation_Id in (
    (requests
     | where name == "GET /api/GetSecret"
     | project operation_Id)
  )
| project timestamp, itemType, name, target, resultCode, success, duration, operation_Id
| order by timestamp asc
```

Expected output: paired `requests` + `dependencies` rows per invocation, with the dependency `target` ending in `.vault.azure.net` and `success = true`.

### Why not just instrument the Power Apps connector?

You can't. The connector runtime is a managed Microsoft service — there is no hook to attach your App Insights SDK to it. Part 3 (Log Analytics on the Key Vault resource) is the supported way to observe the connector path. Part 4 is the only way to observe a **custom code** path with the same level of detail you'd expect from any other instrumented workload.

### Deployment hand-off

When Trinity merges the Function App Bicep module, this section will be expanded with:

- `infra/modules/funcapp.bicep` parameter table
- `scripts/01-deploy.sh` additions (`functionAppName` output placeholder)
- Smoke-test `curl` from the jump host
- The verified KQL with a screenshot

Until then, treat this as the **planned scope**, and use Part 3 as the authoritative validation for the connector path.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| **Label stays blank, no error banner** | Canvas silently swallows connector 403s into a blank variable. Almost always RBAC. See "Surface the error" below, then grant `Key Vault Secrets User`. |
| `AzureKeyVault.*` shows red underline in formula bar | Connection not added to this app. Go to **Data → + Add data → Azure Key Vault** and complete the connection setup (Step 3) before typing any formula. |
| Red underline specifically on `GetSecret("vault-name", "secret-name")` | Wrong signature. `GetSecret` takes **one** argument (secret name only). Vault is bound in the connection. Fix: `AzureKeyVault.GetSecret("demo-secret").value` |
| Connector creation fails: "no network path" | ME may not have refreshed subnet injection — wait 5–10 min, retry. Recheck `docs/managed-environment-setup.md`. |
| `GetSecret` returns 403 in the app | Run the RBAC grant in Pre-flight §c. Allow 2–5 min for role propagation. |
| `AzureKeyVault.GetSecret` returns null | Secret name is case-sensitive. Confirm it is exactly `demo-secret`. Confirm the connection is signed in as `admin@MngEnvMCAP423074.onmicrosoft.com`. |
| App Insights shows no rows | App Insights data export may not be bound yet. Follow [lab-completion-checklist.md → Step 1](../lab-completion-checklist.md#step-1-bind-application-insights-for-telemetry-ppac). Allow 5–10 min after binding. |
| `AzureDiagnostics` returns no rows | KV diagnostic settings stream to `law-pbinet-dev-k6ozyjremes6m`. Verify the `diag-kv` diagnostic setting is enabled (`AuditEvent` category). Logs may take up to 5 min to arrive. |

### Surface the error (blank label diagnostic)

Add a second label to the canvas. Set its `Text` to:

```text
IfError(
    AzureKeyVault.GetSecret("demo-secret").value,
    FirstError.Message & " | " & FirstError.Source,
    "ok: " & AzureKeyVault.GetSecret("demo-secret").value
)
```

Play the app. If the label shows `403` or `Forbidden` — RBAC is missing. Go to Pre-flight §c and grant the role, then wait 5 min.

### Grant RBAC from Azure Portal (if az CLI can't resolve the user)

Azure Portal → `kv-pbinet-dev-k6ozyjreme` → **Access control (IAM)** → **+ Add** → **Add role assignment** → **Key Vault Secrets User** → **Next** → **+ Select members** → type `admin@MngEnvMCAP423074.onmicrosoft.com` → **Select** → **Review + assign**.

Or via CLI (run as a user who CAN resolve the assignee in the tenant):

```bash
az role assignment create \
  --assignee "admin@MngEnvMCAP423074.onmicrosoft.com" \
  --role "Key Vault Secrets User" \
  --scope "/subscriptions/43d55e51-58fe-486f-9e2a-ba56b8dd15de/resourceGroups/rg-pbinet-dev-eastus/providers/Microsoft.KeyVault/vaults/kv-pbinet-dev-k6ozyjreme"
```

Wait 2–5 min for propagation, then retry the app (re-click the button in Play mode).

---

## Cleanup (optional)

```bash
# Delete the demo secret (or leave it for repeat demos)
az keyvault secret delete \
  --vault-name kv-pbinet-dev-k6ozyjreme \
  --name demo-secret
```

Delete the Canvas App: `make.powerapps.com` → **Apps** → `KV VNet Demo` → **⋮** → **Delete**.

---

## Recent changes

- **Bicep automation:** `infra/modules/keyvault.bicep` and `infra/main.bicep` now accept `demoUserPrincipalIds` array parameter to emit `Key Vault Secrets User` role assignments (principalType: User) per OID. Enables fresh deployments to auto-grant the demo operator without post-deployment manual steps.
- **Deploy script:** `scripts/01-deploy.sh` now auto-resolves the signed-in user via `az ad signed-in-user show` and passes their OID to the Bicep `demoUserPrincipalIds` parameter. Supports `--demo-user-oid <oid>` (repeatable) and `--no-auto-demo-user` flags for override.
- **Pre-flight §c:** Rewritten as "Automated" (via `01-deploy.sh`) with manual fallback retained.

---

## References

- [Azure Key Vault connector](https://learn.microsoft.com/en-us/connectors/keyvault/)
- [Virtual network support for Power Platform](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview)
- [Key Vault private link service](https://learn.microsoft.com/en-us/azure/key-vault/general/private-link-service)
- [Connector walkthrough (detailed)](../connectors/keyvault.md)
- [Lab completion checklist](../lab-completion-checklist.md)

---

## Appendix — Verified screen YAML

The YAML below is the exact definition from the verified working Canvas App (Screen1 with Button1 + Label2) that produced the success shown in Part 2. Use it as a copy-paste reference when rebuilding the demo from scratch or diagnosing a broken app against a known-good baseline.

The Label uses the `If(IsBlank(secretValue), ...)` pattern from Step 4, ensuring the empty state is visually distinct from a connector failure.

**Note:** Button1 preserves the user's original text spelling (`"Buttom"`) and trailing newline verbatim to match what has been verified to work. For a polished demo, consider fixing it to `="Button"` — but the YAML below is left unchanged for baseline reproducibility.

```yaml
Screens:
  Screen1:
    Properties:
      LoadingSpinnerColor: =RGBA(56, 96, 178, 1)
    Children:
      - Button1:
          Control: Classic/Button@2.2.0
          Properties:
            BorderColor: =ColorFade(Self.Fill, -15%)
            Color: =RGBA(255, 255, 255, 1)
            DisabledBorderColor: =RGBA(166, 166, 166, 1)
            Fill: =RGBA(56, 96, 178, 1)
            Font: =Font.'Open Sans'
            HoverBorderColor: =ColorFade(Self.BorderColor, 20%)
            HoverColor: =RGBA(255, 255, 255, 1)
            HoverFill: =ColorFade(RGBA(56, 96, 178, 1), -20%)
            OnSelect: =Set(secretValue, AzureKeyVault.GetSecret("demo-secret").value)
            PressedBorderColor: =Self.Fill
            PressedColor: =Self.Fill
            PressedFill: =Self.Color
            Text: |-
              ="Buttom
              "
            X: =40
            Y: =40
      - Label2:
          Control: Label@2.5.1
          Properties:
            BorderColor: =RGBA(0, 18, 107, 1)
            Font: =Font.'Open Sans'
            Text: =If(IsBlank(secretValue), "(click button)", secretValue)
            X: =50
            Y: =170
```
