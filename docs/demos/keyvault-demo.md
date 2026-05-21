# Key Vault demo — VNet-injected Power Platform path

Proves end-to-end that Power Platform reaches a private-only Key Vault (`publicNetworkAccess=Disabled`) through the VNet-injected Managed Environment. Covers a negative test from the public internet, a positive test via Power Apps, and telemetry evidence via App Insights and KV audit logs.

## Contents

- [Pre-flight (one-time setup)](#pre-flight-one-time-setup)
- [Demo Part 1 — Negative test](#demo-part-1--negative-test-proves-public-path-is-blocked)
- [Demo Part 2 — Positive test via Power Apps](#demo-part-2--positive-test-via-power-apps)
- [Demo Part 3 — Evidence the call went through the VNet PE](#demo-part-3--evidence-the-call-went-through-the-vnet-pe)
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

### App Insights — dependency traces

In the Azure portal: **`appi-pbinet-dev`** → **Logs** → run:

```kusto
dependencies
| where timestamp > ago(15m)
| where target contains "vault.azure.net"
| project timestamp, target, resultCode, duration, cloud_RoleName
| order by timestamp desc
```

Expected: a row showing `target = kv-pbinet-dev-k6ozyjreme.vault.azure.net`, `resultCode = 200`.

### KV audit logs — CallerIPAddress confirms private path

In the Azure portal: **`law-pbinet-dev-k6ozyjremes6m`** (Log Analytics workspace) → **Logs** → run:

```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.KEYVAULT"
| where TimeGenerated > ago(15m)
| where OperationName == "SecretGet"
| project TimeGenerated, CallerIPAddress_s, identity_claim_oid_g, requestUri_s, ResultType
| order by TimeGenerated desc
```

Expected: `CallerIPAddress_s` is a private IP (starting `10.10.` for the East delegated subnet or `10.20.` for West), **not** a public internet address. This is the definitive proof the request transited the VNet private endpoint.

### NSP audit logs — Network Security Perimeter observability

The Network Security Perimeter in Learning mode captures every private endpoint inbound attempt in the `NSPAccessLogs` table. Run this query in the same Log Analytics workspace:

```kusto
NSPAccessLogs
| where Category == "NspPrivateInboundAllowed"
| where TimeGenerated > ago(15m)
| where ResourceId contains "Microsoft.KeyVault"
| project TimeGenerated, SourceAddress, DestinationPort, OperationName
| order by TimeGenerated desc
```

Expected: One row per button press, showing the private endpoint inbound traffic. Source address should be a private IP from the delegated subnet (10.10.0.x or 10.20.0.x). This confirms NSP in Learning mode is observing the PE traffic without enforcement.

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
