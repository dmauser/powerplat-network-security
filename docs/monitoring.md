# Network observability and monitoring

This guide documents how to capture and analyze private endpoint inbound traffic (via Network Security Perimeter in Learning mode) and VNet flows (via Traffic Analytics) to verify that Power Platform reaches private Azure resources through delegated subnets only. NSP in Learning mode observes traffic without enforcing restrictions, while VNet flow logs and Traffic Analytics provide layer 3–4 visibility into all flows. Together, they enable operators to audit and troubleshoot the private path.

## Contents

- [Network Security Perimeter in Learning mode](#network-security-perimeter-in-learning-mode)
- [VNet flow logs and Traffic Analytics](#vnet-flow-logs-and-traffic-analytics)
- [Cost expectations](#cost-expectations)
- [Starter KQL queries](#starter-kql-queries)
- [Architecture diagram](#architecture-diagram)
- [Verification steps](#verification-steps)
- [Troubleshooting decision tree](#troubleshooting-decision-tree)
- [Learn more](#learn-more)

## Network Security Perimeter in Learning mode

Azure Network Security Perimeter (NSP) is a regional network access control boundary that sits in front of Azure PaaS resources (Key Vault, SQL, Storage) and logs all inbound traffic without enforcing any restrictions when configured in **Learning mode**. In this lab, NSP is associated with all three PaaS resources in Learning mode, creating a unified audit trail of private endpoint inbound attempts.

### What gets captured

NSP diagnostic logs are written to the `NSPAccessLogs` table in Log Analytics. The lab enables all 13 NSP log categories, meaning you see:

| Category | What it captures |
|----------|------------------|
| `NspPrivateInboundAllowed` | Every inbound attempt arriving via a private endpoint to the associated resource. **This is your primary PE traffic indicator.** |
| `NspPublicInboundPerimeterRulesAllowed` | Public inbound allowed by NSP access rules (empty in Learning mode if no rules are defined). |
| `NspPublicInboundPerimeterRulesDenied` | Public inbound denied by NSP access rules; shows what *would* be denied if mode were Enforced. |
| `NspPublicOutboundPerimeterRulesAllowed` | Public outbound allowed by NSP rules. |
| `NspPublicOutboundPerimeterRulesDenied` | Public outbound denied by NSP rules (baseline for future enforcement). |
| `NspIntraPerimeterInboundAllowed` | Inbound within the same perimeter profile. |
| `NspCrossPerimeterInboundAllowed` | Cross-perimeter inbound via perimeter link. |
| `NspCrossPerimeterOutboundAllowed` | Cross-perimeter outbound via perimeter link. |
| `NspOutboundAttempt` | Outbound attempts from the perimeter. |
| `NspPublicInboundResourceRulesAllowed` | Public inbound allowed by the PaaS resource's own firewall rules. |
| `NspPublicInboundResourceRulesDenied` | Public inbound denied by the resource's firewall rules. |
| `NspPublicOutboundResourceRulesAllowed` | Public outbound allowed by the resource. |
| `NspPublicOutboundResourceRulesDenied` | Public outbound denied by the resource. |

### How NSP Learning mode interacts with `publicNetworkAccess: Disabled`

**NSP in Learning mode is audit-only.** It does not enforce any restrictions or override existing resource-level controls. The existing `publicNetworkAccess: Disabled` setting on Key Vault, SQL, and Storage remains in effect and continues to block any public inbound attempts. NSP simply watches and logs all traffic, including attempts that would be denied by the underlying resource controls.

This means:
- Power Platform flows connecting through the private endpoint path will generate `NspPrivateInboundAllowed` entries.
- Any public-facing denial will generate `NspPublicInboundResourceRulesDenied` entries (confirming the resource is truly private).
- Switching NSP from Learning to Enforced mode later would require explicit access rules and would then actively enforce those rules instead of the resource-level firewall.

**In Learning mode, do not expect NSP to change behavior. Its role is observability only.**

Reference: [Network security perimeter concepts and access modes](https://learn.microsoft.com/en-us/azure/private-link/network-security-perimeter-concepts)
