# Azure Blob Storage connector demo

This walkthrough shows how to read a private blob from the VNet-enabled Managed Environment by using the built-in [Azure Blob Storage connector](https://learn.microsoft.com/en-us/connectors/azureblob/). It complements the Key Vault and SQL demos by showing the same private path with blob data access.

## Contents

- [Overview](#overview)
- [Before you start](#before-you-start)
- [Build the flow](#build-the-flow)
- [Expected result](#expected-result)
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

## Troubleshooting notes

- If authentication fails, make sure you are using Microsoft Entra and RBAC, not SAS tokens or account keys.
- If the connector reaches a public endpoint instead of a private one, check the Blob private DNS zone links in [architecture.md](../architecture.md#private-dns).
- If access is denied, verify the role assignment scope and propagation time. See [troubleshooting.md](../troubleshooting.md#storage-connector-authentication-errors-rbac-vs-sas-vs-key-only-rbac-works-with-private--aad-only-setup).

## Learn more

- [Azure Blob Storage connector](https://learn.microsoft.com/en-us/connectors/azureblob/)
- [Virtual network support overview](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview)
