# Skill: Bicep Private Endpoint ACL Hardening

**Applies to:** Key Vault, Storage, any Azure PaaS resource with `publicNetworkAccess` + `networkAcls`  
**Authored:** 2026-05-20T14:17:03-05:00 by Trinity

---

## Pattern

When a resource has **both** `publicNetworkAccess = 'Disabled'` and `networkAcls.bypass = 'AzureServices'`, the bypass setting is functionally inert but misleading. The bypass property only applies to the public-endpoint firewall; disabling public network access means that firewall never evaluates traffic. Leaving `'AzureServices'` implies a trusted exception path that does not exist, which confuses reviewers and auditors.

### Recommended IaC shape

```bicep
properties: {
  publicNetworkAccess: 'Disabled'
  networkAcls: {
    defaultAction: 'Deny'
    // bypass='None': publicNetworkAccess is Disabled, so the public-endpoint firewall
    // (and its bypass) never fires. 'None' makes the defense-in-depth intent explicit.
    bypass: 'None'
  }
}
```

### When bypass='AzureServices' IS needed

Only set `bypass = 'AzureServices'` if:

1. `publicNetworkAccess` is **Enabled** or **SecuredByPerimeter**, AND
2. A documented Azure service (e.g., Azure Backup, Azure Monitor diagnostic settings writing to Storage) requires the bypass to function, AND
3. You have explicitly verified no private endpoint path is available for that service.

Cite the Microsoft Learn source in a Bicep comment if you keep the bypass.

---

## Scope

Confirmed for:
- `Microsoft.KeyVault/vaults` — [network security docs](https://learn.microsoft.com/en-us/azure/key-vault/general/network-security)
- `Microsoft.Storage/storageAccounts` — [storage firewall docs](https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security)

Check before applying to `Microsoft.Sql/servers` (SQL uses a different firewall model — `publicNetworkAccess` and `restrictOutboundNetworkAccess` rather than `networkAcls`).

---

## Related

- `.squad/decisions/inbox/trinity-region-and-acl.md`
- `infra/modules/keyvault.bicep`
- `infra/modules/storage.bicep`
