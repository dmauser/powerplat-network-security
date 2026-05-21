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

> **Required.** Live check (`2026-05-21`) confirmed `admin@MngEnvMCAP423074.onmicrosoft.com` has **no** role assignments on the vault. The Power Apps Key Vault connector uses the signed-in user's delegated identity (OAuth), so the user reading the secret in the app must hold this role.

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
secretValue
```

### Step 5 — Save, Play, click the button

- **File** → **Save** → **Play** (▶ top-right).
- Click the button.
- Label should display: `Hello from private Key Vault`

This success — while Part 1 showed `ForbiddenByConnection` — proves the Managed Environment is routing through the delegated subnet → private endpoint `pep-kv-pbinet-dev` (NIC IP `10.10.1.4`).

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

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `AzureKeyVault.*` shows red underline in formula bar | Connection not added to this app. Go to **Data → + Add data → Azure Key Vault** and complete the connection setup (Step 3) before typing any formula. |
| Red underline specifically on `GetSecret("vault-name", "secret-name")` | Wrong signature. `GetSecret` takes **one** argument (secret name only). Vault is bound in the connection. Fix: `AzureKeyVault.GetSecret("demo-secret").value` |
| Connector creation fails: "no network path" | ME may not have refreshed subnet injection — wait 5–10 min, retry. Recheck `docs/managed-environment-setup.md`. |
| `GetSecret` returns 403 in the app | Run the RBAC grant in Pre-flight §c. Allow 2–5 min for role propagation. |
| `AzureKeyVault.GetSecret` returns null | Secret name is case-sensitive. Confirm it is exactly `demo-secret`. Confirm the connection is signed in as `admin@MngEnvMCAP423074.onmicrosoft.com`. |
| App Insights shows no rows | App Insights data export may not be bound yet. Follow [lab-completion-checklist.md → Step 1](../lab-completion-checklist.md#step-1-bind-application-insights-for-telemetry-ppac). Allow 5–10 min after binding. |
| `AzureDiagnostics` returns no rows | KV diagnostic settings stream to `law-pbinet-dev-k6ozyjremes6m`. Verify the `diag-kv` diagnostic setting is enabled (`AuditEvent` category). Logs may take up to 5 min to arrive. |

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

## References

- [Azure Key Vault connector](https://learn.microsoft.com/en-us/connectors/keyvault/)
- [Virtual network support for Power Platform](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview)
- [Key Vault private link service](https://learn.microsoft.com/en-us/azure/key-vault/general/private-link-service)
- [Connector walkthrough (detailed)](../connectors/keyvault.md)
- [Lab completion checklist](../lab-completion-checklist.md)
