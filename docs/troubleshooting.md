# Troubleshooting

This guide collects the most likely lab failures and gives a quick symptom, likely diagnosis, and fix for each one. Use it alongside [deployment-guide.md](./deployment-guide.md) when validating the infrastructure and alongside the connector walkthroughs in [./connectors](./connectors/keyvault.md) when a maker flow does not behave as expected.

## Contents

- [403 Forbidden from KV connector even in Managed Env](#403-forbidden-from-kv-connector-even-in-managed-env)
- [Get-EnvironmentRegion returns wrong region](#get-environmentregion-returns-wrong-region)
- [Enable-SubnetInjection fails with policy not found](#enable-subnetinjection-fails-with-policy-not-found)
- [DNS resolves to a public IP from inside Azure](#dns-resolves-to-a-public-ip-from-inside-azure)
- [Subnet too small or AddressSpaceExhausted](#subnet-too-small-or-addressspaceexhausted)
- [enterprisePoliciesPreview not registered](#enterprisepoliciespreview-not-registered-run-00-prereqssh)
- [SQL serverless first-call cold start](#sql-serverless-first-call-cold-start-30s-wake)
- [Storage connector authentication errors](#storage-connector-authentication-errors-rbac-vs-sas-vs-key-only-rbac-works-with-private--aad-only-setup)

## 403 Forbidden from KV connector even in Managed Env

**Symptom**  
The **Azure Key Vault -> Get secret** action returns `403 Forbidden` even though the flow is running in the Managed Environment.

**Diagnosis**  
The most common causes are missing RBAC on the vault, the environment not actually being linked to `<enterprisePolicyArmId>`, a typo in `demo-secret`, DNS resolving `<keyVaultName>.vault.azure.net` to a public address, or configuration drift where the vault networking no longer matches the intended private-only model.

**Fix**  
Check these items in order:

1. Confirm the identity used by the connector can read secrets from the vault.
2. Re-run or verify `Enable-SubnetInjection` and confirm the environment is linked to the expected policy.
3. Confirm the environment geography is still United States and matches the eastus and westus deployment pair.
4. Verify the secret name is exactly `demo-secret`.
5. Confirm the vault hostname resolves to the private endpoint IP and that the private DNS zone is linked to both VNets.

See also [connectors/keyvault.md](./connectors/keyvault.md).

## Get-EnvironmentRegion returns wrong region

**Symptom**  
`Get-EnvironmentRegion -EnvironmentId <id>` returns a geography that does not match the Azure VNet pair you deployed.

**Diagnosis**  
The environment was created in the wrong Power Platform geography, or an existing environment was selected without checking region first.

**Fix**  
Do not force the link. Either recreate or choose a different environment in the correct geography, or redesign the Azure region pair to match the environment. For this lab, the intended geography is **United States**, which maps to **eastus** and **westus** according to the [supported regions documentation](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview#supported-regions).

See [managed-environment-setup.md](./managed-environment-setup.md).

## Enable-SubnetInjection fails with policy not found

**Symptom**  
`Enable-SubnetInjection` fails with an error indicating the policy cannot be found.

**Diagnosis**  
The `<enterprisePolicyArmId>` is wrong, the enterprise policy deployment failed, or the admin account running the linkage lacks the necessary read access to the enterprise policy.

**Fix**  
- Verify the exact ARM ID from the output of `./scripts/01-deploy.sh`.
- Confirm the enterprise policy exists in Azure and is of `kind=NetworkInjection`.
- Ensure the Power Platform admin has permission to read the enterprise policy, as noted in the [setup guidance](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-setup-configure).
- Re-run `./scripts/02-configure-pp-vnet.ps1 -EnvironmentId <id>` with the correct policy identifier.

## DNS resolves to a public IP from inside Azure

**Symptom**  
A check against Key Vault, SQL, or Blob resolves to a public IP instead of a private endpoint address.

**Diagnosis**  
The relevant private DNS zone is not linked to that VNet, the record set was removed, or the request is originating from a network that is not using the linked zone.

**Fix**  
- Verify the correct private DNS zone exists for the target service.
- Verify the zone is linked to **both** VNets, not just the VNet that hosts the private endpoints.
- Recreate the private endpoint DNS integration if records are missing.
- Re-run `./scripts/03-validate-network.sh` after the fix.

See [architecture.md](./architecture.md#private-dns).

## Subnet too small or AddressSpaceExhausted

**Symptom**  
Deployment or runtime validation reports subnet capacity issues such as `AddressSpaceExhausted`.

**Diagnosis**  
The delegated subnet is too small for the environment count or runtime scaling behavior. Once a subnet is delegated, changing its range is not a casual in-place action.

**Fix**  
For a lab, rebuild with a larger CIDR before the subnet is heavily used. For production, follow the subnet sizing guidance in the [overview article](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview#estimating-subnet-size-for-power-platform-environments) and engage Microsoft Support if you must change a delegated range after the fact.

## enterprisePoliciesPreview not registered (run 00-prereqs.sh)

**Symptom**  
The deployment fails because `enterprisePoliciesPreview` is not registered.

**Diagnosis**  
The subscription prerequisites were skipped or incomplete.

**Fix**  
Run:

```bash
./scripts/00-prereqs.sh
```

Then confirm the feature registration has completed before you retry `./scripts/01-deploy.sh`.

## SQL serverless first-call cold start (30s wake)

**Symptom**  
The SQL connector seems slow or times out on the first call.

**Diagnosis**  
If the lab uses Azure SQL serverless, the compute can auto-pause when idle and need time to resume.

**Fix**  
Wait roughly 30 seconds and retry the first query. For smoother demos, run a warm-up query shortly before the meeting or consider a non-paused SKU if predictable response time matters more than cost.

See [cost-control.md](./cost-control.md).

## Storage connector authentication errors (RBAC vs SAS vs key — only RBAC works with private + AAD-only setup)

**Symptom**  
The Azure Blob Storage connector cannot authenticate or returns access denied.

**Diagnosis**  
The connection is using the wrong auth model for the lab, such as SAS or account keys, or the Microsoft Entra principal lacks **Storage Blob Data Reader** permission.

**Fix**  
Use Microsoft Entra ID authentication and Azure RBAC. Confirm the identity has the correct data-plane role assignment and allow time for RBAC propagation. Avoid mixing SAS or shared key patterns into this demo because the private and AAD-first design is meant to show an RBAC-controlled access path.

See [connectors/blob.md](./connectors/blob.md) and [security-notes.md](./security-notes.md).
