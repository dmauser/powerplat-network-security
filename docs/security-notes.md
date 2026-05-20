# Security notes

This note captures the key security choices behind the demo so you can explain why the lab is built the way it is and what would carry forward into a production design. The main themes are least-privilege RBAC, Microsoft Entra-first authentication, private endpoint enforcement, and enough logging to prove that traffic stayed private.

## Contents

- [Overview](#overview)
- [Least-privilege RBAC](#least-privilege-rbac)
- [AAD-only authentication for SQL](#aad-only-authentication-for-sql)
- [Key Vault purge protection](#key-vault-purge-protection)
- [Why public network access is disabled](#why-public-network-access-is-disabled)
- [Secret rotation guidance](#secret-rotation-guidance)
- [Logging and auditing](#logging-and-auditing)
- [Related guidance](#related-guidance)

## Overview

Power Platform virtual network support is most convincing when the private-resource posture is real, not simulated. In this lab that means Key Vault, SQL, and Storage stay private, access is granted through Microsoft Entra ID and Azure RBAC, and the Power Platform environment reaches those services through delegated subnets and private DNS rather than public allowlists.

## Least-privilege RBAC

Use narrow scopes and data-plane roles where possible.

Suggested assignments for the demo identity represented by `<userAssignedIdentityPrincipalId>`:

- **Key Vault Secrets User** scoped to the Key Vault that contains `demo-secret`.
- **Storage Blob Data Reader** scoped to the storage account or just the `demo` container.
- **Azure SQL logical server Microsoft Entra admin** set on the SQL logical server, with additional least-privilege database access if your SQL access model requires it.

Operational guidance:

- Prefer resource-level or container-level scope over subscription-wide assignments.
- Avoid Owner or Contributor for runtime identities.
- Separate deployment permissions from runtime data access whenever possible.

## AAD-only authentication for SQL

This lab uses Microsoft Entra-based SQL access rather than SQL authentication. That keeps the demo aligned with the rest of the identity story and avoids introducing long-lived SQL usernames and passwords just to prove private connectivity.

Use this design principle:

- No SQL logins for the demo path.
- Microsoft Entra integrated authentication for the SQL connector.
- Server and database permissions granted through Entra-backed administration and database principals.

## Key Vault purge protection

Enable soft delete and purge protection on the Key Vault used for the demo. Even in a lab, purge protection reinforces the message that secrets are treated as production-like assets and should not be casually destroyed or permanently removed after accidental deletion.

This also makes the Key Vault portion of the demo more credible when customers ask how the same pattern would look in production.

## Why public network access is disabled

All three demo services should keep `publicNetworkAccess=Disabled`:

- Key Vault
- Azure SQL Database
- Storage account

That setting is essential to the story. If public access stays enabled, the audience can reasonably ask whether the connector succeeded because private access was really in place or simply because the service still had a public path available. Disabling public access proves the environment is relying on private endpoints, private DNS, and the delegated subnet path described in [architecture.md](./architecture.md).

For this repo specifically, treat network ACL bypass settings as defense-in-depth. Both Key Vault and Storage set `networkAcls.bypass = 'None'` because `publicNetworkAccess = 'Disabled'` already prevents any inbound public traffic; the bypass property applies only to the public-endpoint firewall, which is off, so retaining `'AzureServices'` would add confusion without adding protection. The resulting posture is: **all access to Key Vault and Storage flows exclusively through private endpoints; no public-endpoint bypass is in effect**.

## Secret rotation guidance

For the Key Vault demo and any production follow-on:

- Store secrets in Azure Key Vault with normal versioning enabled.
- Let connector references or downstream callers retrieve the current version unless you have a reason to pin to a specific version.
- Rotate secrets by creating a new version and validating the flow again.
- Keep the demo secret simple, but keep the rotation story realistic.

## Logging and auditing

For the lab, comprehensive diagnostics prove the private path and catch public access attempts. The deployment provisions diagnostic settings for Key Vault (`AuditEvent`, `AzurePolicyEvaluationDetails`, `AllMetrics`), SQL (`Errors`, `Security`, `Timeouts`), Storage (`StorageRead/Write/Delete`), and private endpoints (`AllMetrics`), all flowing to a Log Analytics workspace.

**Essential visibility:**
- Key Vault audit events capture all secret/key access with caller IP and identity.
- Denied public-endpoint attempts are logged with HTTP 403/401 and public IP source—see [monitoring.md](./monitoring.md) for queries.
- NSG flow logs can be added later if you extend the network with NSGs.
- Connector run history inside Power Automate shows client-side timing and error context.
- A private-name-resolution check from inside the injected path, such as the Managed Environment runtime or a jump host in one of the VNets.

See [monitoring.md](./monitoring.md) for full telemetry setup, KQL queries, and troubleshooting workflows.

Be careful not to overstate what an external validation script proves. A public-side DNS lookup can confirm the Private Link CNAME chain and control-plane settings, but only an in-path test proves that the runtime resolved the service FQDN to the private endpoint IP.

For a production expansion, send Key Vault and other service diagnostics to Log Analytics and centralize alerting and retention policy. That future-state recommendation is part of [expansion-roadmap.md](./expansion-roadmap.md).

## Related guidance

- [architecture.md](./architecture.md)
- [troubleshooting.md](./troubleshooting.md)
- [cost-control.md](./cost-control.md)
