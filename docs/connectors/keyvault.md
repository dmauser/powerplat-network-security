# Azure Key Vault connector demo

This walkthrough shows a maker how to prove the primary lab scenario: a flow in the VNet-enabled Managed Environment reads `demo-secret` from a private Azure Key Vault by using the built-in [Azure Key Vault connector](https://learn.microsoft.com/en-us/connectors/keyvault/). Use this after [deployment-guide.md](../deployment-guide.md) confirms that the environment is linked to `<enterprisePolicyArmId>`.

## Contents

- [Overview](#overview)
- [Before you start](#before-you-start)
- [Build the flow](#build-the-flow)
- [Expected result](#expected-result)
- [Without VNet support](#without-vnet-support)
- [Testing the private path](#testing-the-private-path)
- [Troubleshooting checklist](#troubleshooting-checklist)
- [Learn more](#learn-more)

## Overview

The Key Vault connector is the clearest first demo because the secret read is simple to explain and easy to validate. In this lab, the vault stays private, `publicNetworkAccess=Disabled`, and the flow succeeds only because the Managed Environment is linked to the enterprise policy and resolves `<keyVaultName>.vault.azure.net` through private DNS.

## Before you start

Confirm all of the following:

- You are working inside the linked Managed Environment from [managed-environment-setup.md](../managed-environment-setup.md).
- The Azure deployment has emitted `<keyVaultName>` and `<keyVaultUri>`.
- The vault already contains a secret named `demo-secret`.
- The required RBAC assignment is in place for the calling identity as described in [security-notes.md](../security-notes.md).

## Build the flow

1. Open **Power Automate** in the target Managed Environment.
2. Create a new instant cloud flow with a **manual trigger**.
3. Add a new action: **Azure Key Vault -> Get secret**.
4. Create or select the connection.
5. For authentication, choose either:
   - **Service principal**, or
   - **Microsoft Entra ID (OAuth)**
6. Provide the following values when prompted:
   - Client ID: the UAMI client ID or the service principal client ID you are using for the demo.
   - Tenant ID: your Microsoft Entra tenant ID.
   - Vault name: `<keyVaultName>`
7. In the action settings, set **Secret name** to `demo-secret`.
8. Save the flow.
9. Test the flow manually.

## Expected result

A successful run should show:

- HTTP `200` or a successful action status.
- The value of `demo-secret` in the action output.
- No requirement to enable public access on the vault.

Use the output as the baseline proof point for the rest of the lab.

## Without VNet support

If you repeat the same action from a non-Managed or non-linked environment, the likely outcome is `403 Forbidden`. The reason is not usually the action itself; it is that the environment is not using the delegated subnet path required by [Power Platform virtual network support](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview), so the request cannot reach the private-only vault correctly.

## Testing the private path

After building the flow, validate that it is using the private path by confirming that public access to the vault stays blocked while the Managed Environment run succeeds.

### Public denial probe from your workstation

From your local machine (not the Managed Environment), prove the public endpoint is blocked:

```bash
curl -sS -o /dev/null -w "%{http_code}\n" "https://<keyVaultName>.vault.azure.net/secrets/demo-secret?api-version=7.4"
# Expected: 403
```

This `403` confirms that `publicNetworkAccess=Disabled` is still enforced. The only way the Managed Environment flow succeeds is through the private endpoint path.

### Verify private DNS resolution

From the Azure portal or via `az network private-dns record-set a show`:

```bash
az network private-dns record-set a show \
  --resource-group <resource-group> \
  --zone-name privatelink.vaultcore.azure.net \
  --name <keyVaultName> \
  --query aRecords[0].ipv4Address -o tsv
# Expected: private endpoint IP (e.g., 10.10.1.4)
```

Compare this private IP to the Azure portal view of the private endpoint in `snet-pep`.

### Private DNS zone link verification

Confirm that the private DNS zone is linked to both VNets (required for cross-VNet access):

```bash
az network private-dns link vnet list \
  --resource-group <resource-group> \
  --zone-name privatelink.vaultcore.azure.net \
  --query "[].virtualNetwork.id" -o tsv
# Expected: both VNet resource IDs (eastus and westus)
```

## Troubleshooting checklist

If you still see `403 Forbidden` even in the Managed Environment, check the following in order:

1. **RBAC missing**: confirm the calling identity has permission to read secrets from the vault.
2. **Environment not linked**: verify `Enable-SubnetInjection` completed successfully and the environment is attached to `<enterprisePolicyArmId>`.
3. **Region mismatch**: verify `Get-EnvironmentRegion` aligns with the paired eastus and westus deployment.
4. **Secret name typo**: confirm the secret really is named `demo-secret`.
5. **DNS issue**: verify `<keyVaultName>.vault.azure.net` resolves to the private endpoint IP from the Azure side.

For deeper fixes, see [troubleshooting.md](../troubleshooting.md#403-forbidden-from-kv-connector-even-in-managed-env).

## Learn more

- [Azure Key Vault connector](https://learn.microsoft.com/en-us/connectors/keyvault/)
- [Virtual network support overview](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview)
- [Azure Key Vault private link](https://learn.microsoft.com/en-us/azure/key-vault/general/private-link-service)
