# Custom HTTP connector demo

This walkthrough shows how to build a custom connector from scratch and call the Azure Key Vault REST API over the same private path used by the built-in connectors. The goal is to prove that Power Platform virtual network support is a general HTTPS connectivity pattern, not just a one-off Key Vault connector demo.

## Contents

- [Overview](#overview)
- [Before you start](#before-you-start)
- [Create the custom connector](#create-the-custom-connector)
- [Configure security](#configure-security)
- [Add the action](#add-the-action)
- [Test the connector](#test-the-connector)
- [Testing the private path](#testing-the-private-path)
- [Why this matters](#why-this-matters)
- [Learn more](#learn-more)

## Overview

The custom connector targets the Key Vault REST endpoint directly:

```text
GET https://<keyVaultName>.vault.azure.net/secrets/demo-secret?api-version=7.4
```

For demo simplicity, this connector uses a separate app registration with OAuth 2.0 and a client secret. That keeps the setup straightforward in the maker experience, but for production design the UAMI-based pattern used elsewhere in this lab is generally preferred.

## Before you start

Confirm all of the following:

- The target environment is the linked Managed Environment from [managed-environment-setup.md](../managed-environment-setup.md).
- `<keyVaultName>` is available from deployment outputs.
- A separate demo-only app registration exists with permission to call Azure Key Vault.
- You know the tenant ID, client ID, and client secret for that demo-only app registration.

## Create the custom connector

1. Open **Power Automate** or **Power Apps** in the Managed Environment.
2. Go to **Custom connectors**.
3. Select **New custom connector**.
4. Choose to create it from blank; no OpenAPI file is required.
5. Give it a name such as `KeyVault Private REST Demo`.
6. Set the host to:

```text
<keyVaultName>.vault.azure.net
```

7. Set the base URL if prompted to `/`.

## Configure security

On the **Security** tab, configure:

- Authentication type: **OAuth 2.0**
- Identity provider: **Microsoft Entra ID**
- Resource URL: `https://vault.azure.net`
- Client ID: `<clientId>` from the separate app registration
- Client secret: `<clientSecret>` from the separate app registration
- Tenant ID or authorization endpoints as required by the maker UX

Use this note during the demo:

> This app registration and client secret are for demo convenience only. In production, prefer managed identity or a centrally governed service principal pattern instead of distributing secrets.

## Add the action

Create one action with the following request definition:

```text
GET /secrets/{secret-name}?api-version=7.4
```

Suggested configuration:

- Operation ID: `GetSecret`
- Summary: `Get Key Vault secret`
- Path parameter: `secret-name`

If you add a sample response, use a trimmed example from the Key Vault REST output so the test blade is easier to read.

## Test the connector

1. Create a connection for the custom connector.
2. Open the **Test** tab.
3. Invoke the action with:
   - `secret-name`: `demo-secret`
4. Run the request.

Expected result:

- HTTP `200`
- A JSON response that includes the secret identifier and value metadata for `demo-secret`

## Testing the private path

After building and testing the connector, validate that the custom HTTP call uses the private endpoint path the same way the built-in connectors do.

### Public denial probe from your workstation

From your local machine, prove the public Key Vault REST API returns `403`:

```bash
curl -sS -o /dev/null -w "%{http_code}\n" "https://<keyVaultName>.vault.azure.net/secrets/demo-secret?api-version=7.4"
# Expected: 403
```

The same endpoint call succeeds in the Managed Environment flow because of the private endpoint path.

### Verify private DNS resolution for the host

From the Azure portal or via `az network private-dns record-set a show`:

```bash
az network private-dns record-set a show \
  --resource-group <resource-group> \
  --zone-name privatelink.vaultcore.azure.net \
  --name <keyVaultName> \
  --query aRecords[0].ipv4Address -o tsv
# Expected: private endpoint IP (e.g., 10.10.1.4)
```

The custom connector resolves `<keyVaultName>.vault.azure.net` to this private IP when invoked from the Managed Environment.

### Monitor the custom connector call

After running the custom connector in the Managed Environment, check Key Vault diagnostic logs to see that the request came from a private IP (the delegated subnet CIDR range):

```bash
az monitor log-analytics query \
  --workspace <workspace-id> \
  --analytics-query "AzureDiagnostics | where ResourceProvider == 'MICROSOFT.KEYVAULT' | where OperationName == 'SecretGet' | order by TimeGenerated desc | limit 1"
```

The source IP should be within your VNet address space (e.g., `10.10.x.x` or `10.20.x.x`), not a public Azure datacenter IP.

## Why this matters

This test demonstrates the broader value proposition of virtual network support: once the Managed Environment is linked to the enterprise policy, the delegated subnet path can support any correctly authenticated HTTPS API that is reachable through your private network design. That is why the custom connector sits alongside the first-party connector demos in [deployment-guide.md](../deployment-guide.md) and [demo-script.md](../demo-script.md).

## Learn more

- [Virtual network support overview](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview)
- [Azure Key Vault connector](https://learn.microsoft.com/en-us/connectors/keyvault/)
- [Azure Key Vault private link](https://learn.microsoft.com/en-us/azure/key-vault/general/private-link-service)
