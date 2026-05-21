# Tank NSP prereqs update

This note records the NSP and Traffic Analytics prerequisite plumbing added to the shell scripts on 2026-05-21 so the audit-only deployment path is repeatable and idempotent.

## Contents

- [Summary](#summary)
- [Added registrations](#added-registrations)
- [Skipped items](#skipped-items)
- [Why this matters](#why-this-matters)

## Summary

Tank updated `scripts/00-prereqs.sh` to verify Azure provider and feature registration state before making changes, then wait only when a registration is actually needed or already in progress. Tank updated `scripts/01-deploy.sh` to surface the new NSP and flow-log outputs and to print the LAW status message operators need after deployment.

## Added registrations

- `Microsoft.Network` remains in the prereq provider list and is explicitly refreshed after the NSP feature finishes registering.
- `Microsoft.Network/AllowNSPInPublicPreview` was added because Morpheus's NSP audit spec still requires the public preview feature gate before deploying `Microsoft.Network/networkSecurityPerimeters` resources.
- `Microsoft.Insights` was added because NSP diagnostic settings and Traffic Analytics depend on Azure Monitor plumbing.
- Existing `Microsoft.PowerPlatform/accounts/enterprisePolicies` feature registration remains in place because the lab still needs the Power Platform enterprise policy preview path.

## Skipped items

- `Microsoft.NetworkAnalytics` was intentionally not added. Morpheus's spec states Traffic Analytics is part of `Microsoft.Network` / Network Watcher and that Azure auto-provisions the `NetworkMonitoring` solution plus `AzureNetworkAnalytics_CL` after the first processed flow-log batch.
- No manual `az monitor log-analytics solution create` step was added to `scripts/01-deploy.sh` for the same reason: the solution is expected to appear automatically when Traffic Analytics is enabled and starts processing data.

## Why this matters

These changes make the prereq path safe to rerun on partially prepared subscriptions, which matches Tank's idempotent-script charter. They also give operators immediate post-deploy confirmation that NSP is in Learning mode and where to look in Log Analytics for `NSPAccessLogs` while waiting for Traffic Analytics data to land.
