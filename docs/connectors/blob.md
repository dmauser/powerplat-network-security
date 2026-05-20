# Azure Blob Storage connector demo

This walkthrough shows how to read a private blob from the VNet-enabled Managed Environment by using the built-in [Azure Blob Storage connector](https://learn.microsoft.com/en-us/connectors/azureblob/). It complements the Key Vault and SQL demos by showing the same private path with blob data access.

## Contents

- [Overview](#overview)
- [Before you start](#before-you-start)
- [Build the flow](#build-the-flow)
- [Expected result](#expected-result)
- [Testing the private path](#testing-the-private-path)
- [Troubleshooting notes](#troubleshooting-notes)
- [Learn more](#learn-more)

## Overview

The Blob connector uses Microsoft Entra-based authentication and Azure RBAC to read `demo/hello.txt` from the private storage account `<storageAccountName>`. The storage account remains private, blob access resolves through the private endpoint, and the flow proves that VNet support works for another common Azure data service.

## Before you start

Confirm all of the following:

- You are in the linked Managed Environment from [managed-environment-setup.md](../managed-environment-setup.md).
- The deployment output includes `<storageAccountName>`.
- The storage account contains container `demo` and blob `hello.txt`.
- The calling identity has **Storage Blob Data Reader** or equivalent least-privilege access, as described in [security-notes.md](../security-notes.md).

## Build the flow

1. Open **Power Automate** in the Managed Environment.
2. Create a new instant cloud flow with a **manual trigger**.
3. Add action: **Azure Blob Storage -> Get blob content (V2)**.
4. Create the connection using **Microsoft Entra ID** with the service principal or UAMI-backed identity chosen for the demo.
5. Provide the storage account name: `<storageAccountName>`.
6. Configure the action:
   - Container: `demo`
   - Blob: `hello.txt`
7. Save the flow.
8. Test the flow manually.

## Expected result

A successful run should return the file bytes or rendered text for `demo/hello.txt`. For the demo, keep the blob content human-readable so the audience can immediately recognize the success case.

## Testing the private path

After building the flow, validate both deny paths (anonymous and SAS-over-public) and then confirm the Managed Environment allow path works.

### Anonymous denial probe from your workstation

From your local machine, prove that anonymous access to the blob returns `403`:

```bash
curl -sS -o /dev/null -w "%{http_code}\n" "https://<storageAccountName>.blob.core.windows.net/demo/hello.txt"
# Expected: 403
```

This confirms that `publicNetworkAccess=Disabled` is enforced for the public endpoint.

### SAS-over-public denial probe

Create a time-limited SAS token and show that it also returns `403` when used over the public URL:

```bash
RESOURCE_GROUP="$(az resource list --name <storageAccountName> --resource-type Microsoft.Storage/storageAccounts --query '[0].resourceGroup' -o tsv)"
ACCOUNT_KEY="$(az storage account keys list -g "$RESOURCE_GROUP" -n <storageAccountName> --query '[0].value' -o tsv)"
EXPIRY="$(pwsh -NoLogo -NoProfile -Command "(Get-Date).ToUniversalTime().AddMinutes(15).ToString('yyyy-MM-ddTHH:mmZ')")"
SAS_TOKEN="$(az storage blob generate-sas --account-name <storageAccountName> --account-key "$ACCOUNT_KEY" --container-name demo --name hello.txt --permissions r --expiry "$EXPIRY" -o tsv)"
curl -sS -o /dev/null -w "%{http_code}\n" "https://<storageAccountName>.blob.core.windows.net/demo/hello.txt?$SAS_TOKEN"
# Expected: 403
```

Even with a valid SAS token, the public endpoint is denied. This proves the storage account is truly private.

### Verify private DNS resolution

From the Azure portal or via `az network private-dns record-set a show`:

```bash
az network private-dns record-set a show \
  --resource-group <resource-group> \
  --zone-name privatelink.blob.core.windows.net \
  --name <storageAccountName> \
  --query aRecords[0].ipv4Address -o tsv
# Expected: private endpoint IP (e.g., 10.10.1.6)
```

The Managed Environment flow resolves this name to the private endpoint IP, not the public blob endpoint.

### Private DNS zone link verification

Confirm the private DNS zone is linked to both VNets:

```bash
az network private-dns link vnet list \
  --resource-group <resource-group> \
  --zone-name privatelink.blob.core.windows.net \
  --query "[].virtualNetwork.id" -o tsv
# Expected: both VNet resource IDs (eastus and westus)
```

## Troubleshooting notes

- If authentication fails, make sure you are using Microsoft Entra and RBAC, not SAS tokens or account keys.
- If the connector reaches a public endpoint instead of a private one, check the Blob private DNS zone links in [architecture.md](../architecture.md#private-dns).
- If access is denied, verify the role assignment scope and propagation time. See [troubleshooting.md](../troubleshooting.md#storage-connector-authentication-errors-rbac-vs-sas-vs-key-only-rbac-works-with-private--aad-only-setup).

## Learn more

- [Azure Blob Storage connector](https://learn.microsoft.com/en-us/connectors/azureblob/)
- [Virtual network support overview](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview)
