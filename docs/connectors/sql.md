# SQL Server connector demo

This walkthrough shows how to validate private Azure SQL Database access from the VNet-enabled Managed Environment by using the built-in [SQL Server connector](https://learn.microsoft.com/en-us/connectors/sql/). It is the second connector demo in the lab and proves that the same subnet injection pattern works beyond Key Vault.

## Contents

- [Overview](#overview)
- [Before you start](#before-you-start)
- [Build the flow](#build-the-flow)
- [Expected result](#expected-result)
- [Notes](#notes)
- [Learn more](#learn-more)

## Overview

In this lab, the SQL Server connector reads rows from `dbo.Sales` in the private database named `<sqlDatabaseName>`. The server is reached through `<sqlServerFqdn>`, private DNS resolves that name to the private endpoint, and Microsoft Entra-based authentication is used instead of SQL logins.

## Before you start

Confirm all of the following:

- The environment is the linked Managed Environment from [managed-environment-setup.md](../managed-environment-setup.md).
- The deployment output includes `<sqlServerFqdn>` and `<sqlDatabaseName>`.
- The `dbo.Sales` table already exists and contains sample rows.
- The SQL logical server is configured for Microsoft Entra administration as described in [security-notes.md](../security-notes.md).

## Build the flow

1. Open **Power Automate** in the Managed Environment.
2. Create a new instant cloud flow with a **manual trigger**.
3. Add action: **SQL Server -> Get rows (V2)**.
4. Create the connection with these values:
   - Server: `<sqlServerFqdn>`
   - Database: `salesdb` or `<sqlDatabaseName>` if your deployment used a different logical name
   - Authentication type: **Microsoft Entra integrated**
5. In the action configuration:
   - Table: `dbo.Sales`
6. Save the flow.
7. Test the flow manually.

## Expected result

A successful run should show one or more rows returned from `dbo.Sales` in the test output. Use those rows to explain that the SQL connection stayed private while still using a standard first-party Power Platform connector.

## Notes

- If the database is serverless, the first call can take around 30 seconds while the compute tier wakes up. See [troubleshooting.md](../troubleshooting.md#sql-serverless-first-call-cold-start-30s-wake).
- If authentication fails, double-check the Entra admin and any contained database user or access model you chose for the demo.
- If name resolution returns a public endpoint, revisit the private DNS links described in [architecture.md](../architecture.md#private-dns).

## Learn more

- [SQL Server connector](https://learn.microsoft.com/en-us/connectors/sql/)
- [Virtual network support overview](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview)
