# SQL Server connector demo

This walkthrough shows how to validate private Azure SQL Database access from the VNet-enabled Managed Environment by using the built-in [SQL Server connector](https://learn.microsoft.com/en-us/connectors/sql/). It is the second connector demo in the lab and proves that the same subnet injection pattern works beyond Key Vault.

## Contents

- [Overview](#overview)
- [Before you start](#before-you-start)
- [Build the flow](#build-the-flow)
- [Expected result](#expected-result)
- [Testing the private path](#testing-the-private-path)
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

## Testing the private path

After building the flow, validate the deny and allow paths to confirm private-only access is working.

### Public denial probe from your workstation

From your local machine, prove the public SQL port is blocked:

```powershell
Test-NetConnection -ComputerName '<sqlServerFqdn>' -Port 1433 |
  Select-Object ComputerName, RemotePort, TcpTestSucceeded
# Expected: TcpTestSucceeded = False
```

This confirms that the server is not reachable over public TCP 1433. The Managed Environment flow succeeds only because it uses the private endpoint path.

### Verify private DNS resolution

From the Azure portal or via `az network private-dns record-set a show`:

```bash
az network private-dns record-set a show \
  --resource-group <resource-group> \
  --zone-name privatelink.database.windows.net \
  --name '<sqlServerFqdn>' \
  --query aRecords[0].ipv4Address -o tsv
# Expected: private endpoint IP (e.g., 10.10.1.5)
```

The Managed Environment flow resolves this FQDN to the private endpoint IP, not the public endpoint.

### Private DNS zone link verification

Confirm the private DNS zone is linked to both VNets:

```bash
az network private-dns link vnet list \
  --resource-group <resource-group> \
  --zone-name privatelink.database.windows.net \
  --query "[].virtualNetwork.id" -o tsv
# Expected: both VNet resource IDs (eastus and westus)
```

Both VNets must be linked so that flows from either delegated subnet can resolve the private endpoint.

### Verify via telemetry

Check the SQL error and security logs to confirm the successful login and query execution came from the private delegated subnet IP. See [monitoring.md](../monitoring.md) for detailed telemetry queries on SQL access patterns.

## Notes

- If the database is serverless, the first call can take around 30 seconds while the compute tier wakes up. See [troubleshooting.md](../troubleshooting.md#sql-serverless-first-call-cold-start-30s-wake).
- If authentication fails, double-check the Entra admin and any contained database user or access model you chose for the demo.
- If name resolution returns a public endpoint, revisit the private DNS links described in [architecture.md](../architecture.md#private-dns).

## Learn more

- [SQL Server connector](https://learn.microsoft.com/en-us/connectors/sql/)
- [Virtual network support overview](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview)
