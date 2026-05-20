# Cost control

This note explains how to keep the demo inexpensive while still preserving the architecture required for Power Platform virtual network support. The Azure footprint is small by design, while the Power Platform Managed Environment discussion is primarily about licensing entitlement rather than Azure consumption.

## Contents

- [Overview](#overview)
- [Idle Azure cost profile](#idle-azure-cost-profile)
- [SQL serverless auto-pause](#sql-serverless-auto-pause)
- [Managed Environment licensing](#managed-environment-licensing)
- [Cleanup order](#cleanup-order)
- [Related guidance](#related-guidance)

## Overview

For a demo lab, the always-on network components are usually inexpensive compared with leaving a larger database tier running. The goal is to keep the Azure side to a few USD per month when idle, use serverless or low-cost SKUs where practical, and clean up promptly with `./scripts/05-cleanup.sh` after the demo.

## Idle Azure cost profile

Typical idle cost contributors in this lab are:

- Private endpoints for Key Vault, SQL, and Storage.
- Private DNS zones.
- Small-footprint Key Vault and Storage resources.
- Azure SQL Database, which is often the largest variable component if it is not serverless or paused.
- Optional monitoring resources if you extend the lab with diagnostics or Log Analytics later.

Because Azure prices change, treat this as a qualitative rule of thumb instead of a quote: the network and storage portion of the lab should remain modest, and the SQL choice is the main lever that changes the monthly total.

## SQL serverless auto-pause

If your deployment uses Azure SQL serverless:

- Enable auto-pause to reduce idle compute cost.
- Expect a cold start on the first request after an idle period.
- Warm the database before a customer demo if you want the SQL connector step to feel instantaneous.

See the runtime tradeoff in [troubleshooting.md](./troubleshooting.md#sql-serverless-first-call-cold-start-30s-wake).

## Managed Environment licensing

Managed Environment eligibility is a **Power Platform licensing** topic, not an Azure-billed resource. For this documentation set, pricing is intentionally left qualitative because license packaging and price points can change over time.

Use these customer-facing statements:

- The demo user should have a qualifying **per-user Power Platform plan** or another eligible standalone license.
- Managed Environment entitlement comes from Power Platform or Dynamics licensing, not from the Azure subscription used for the VNets and private endpoints.
- For current pricing, direct customers to the official [Power Platform pricing page](https://www.microsoft.com/en-us/power-platform/pricing).

For licensing context, also review the [Managed Environments overview](https://learn.microsoft.com/en-us/power-platform/admin/managed-environment-overview).

## Cleanup order

Use the cleanup sequence below after the demo:

1. Export any screenshots, outputs, or evidence you want to keep.
2. Run:

```bash
./scripts/05-cleanup.sh
```

3. Confirm Azure-side resources are deleted.
4. Remember that Managed Environment licensing is a **tenant** concern and is not removed by the Azure cleanup script.

## Related guidance

- [deployment-guide.md](./deployment-guide.md)
- [security-notes.md](./security-notes.md)
- [expansion-roadmap.md](./expansion-roadmap.md)
