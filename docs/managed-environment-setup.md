# Managed Environment setup

This walkthrough explains how to prepare the Power Platform side of the lab before any Azure network injection steps run. The goal is to end with a United States environment that is managed, licensed correctly for the demo audience, and ready to be linked to `<enterprisePolicyArmId>` by `./scripts/02-configure-pp-vnet.ps1`.

## Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Create or select a United States environment](#create-or-select-a-united-states-environment)
- [Promote the environment to Managed Environment](#promote-the-environment-to-managed-environment)
- [Find the environment ID](#find-the-environment-id)
- [Validate the region with PowerShell](#validate-the-region-with-powershell)
- [Next step](#next-step)

## Overview

Virtual network support requires a [Managed Environment](https://learn.microsoft.com/en-us/power-platform/admin/managed-environment-overview), so the Power Platform admin setup happens before the subnet injection script is run. Use the [Power Platform admin center](https://admin.powerplatform.microsoft.com/) to create or inspect the environment, then validate the environment geography with `Get-EnvironmentRegion` from the [Microsoft.PowerPlatform.EnterprisePolicies module](https://learn.microsoft.com/en-us/powershell/module/microsoft.powerplatform.enterprisepolicies/).

## Prerequisites

Before you begin:

- You need the **Power Platform administrator** role, as described in the [setup guidance](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-setup-configure).
- The demo user who creates or runs flows should have a qualifying standalone Power Platform license. For lab planning, use a **per-user Power Platform plan** or another qualifying license that includes Managed Environment entitlement, as described in the [Managed Environments overview](https://learn.microsoft.com/en-us/power-platform/admin/managed-environment-overview).
- Avoid Developer Plan-only assumptions for the main demo because Managed Environment entitlement is not included for users running assets under the Developer Plan.

## Create or select a United States environment

1. Go to [Power Platform admin center](https://admin.powerplatform.microsoft.com/).
2. Select **Environments**.
3. Either pick an existing environment or create a new one.
4. Make sure the environment region is **United States**.
5. If you are creating a new environment, record the display name you will use throughout the lab.

Recommendations for this lab:

- Keep one **non-Managed** environment available for the before-and-after demo in [demo-script.md](./demo-script.md).
- Keep one **Managed Environment** in the same tenant for the successful connector demonstrations.
- If you already have a suitable US-region sandbox or production environment, you can reuse it.

## Promote the environment to Managed Environment

1. In [Power Platform admin center](https://admin.powerplatform.microsoft.com/), open the target environment.
2. Open **Settings**.
3. Find the **Managed Environment** section.
4. If the environment is not already managed, choose the option to enable or promote it to a Managed Environment.
5. Save the change and wait for the environment status to finish updating.

After this step, the environment is eligible for the subnet injection linkage described in [deployment-guide.md](./deployment-guide.md).

## Find the environment ID

You need the environment ID for `./scripts/02-configure-pp-vnet.ps1 -EnvironmentId <id>`.

Common ways to find it:

- In Power Platform admin center, open the environment details page and copy the environment ID from the details pane.
- If the portal shows a URL with the environment identifier, copy the GUID from that page.
- If you already use Power Platform PowerShell or admin APIs internally, you can also retrieve the environment record there and copy the environment ID.

Store the value somewhere convenient for the rest of the deployment walkthrough.

```powershell
$environmentId = "<environmentId>"
```

## Validate the region with PowerShell

Use the enterprise policies module before you link the policy so you can verify the environment is in the expected geography.

```powershell
Import-Module Microsoft.PowerPlatform.EnterprisePolicies
Get-EnvironmentRegion -EnvironmentId "<environmentId>"
```

Expected result for this lab:

- The returned geography must align with **United States**.
- The paired Azure regions used by the lab must therefore be **eastus** and **westus**, as documented in [architecture.md](./architecture.md) and the [supported regions section](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview#supported-regions).

If the region is not United States, do not continue with the US deployment. Instead, either recreate the environment in the correct geography or build a different paired-region variant as outlined in [expansion-roadmap.md](./expansion-roadmap.md).

## Next step

After the environment is managed and the region is validated:

1. Run the Azure-side prerequisites and deployment in [deployment-guide.md](./deployment-guide.md).
2. Use the environment ID with `./scripts/02-configure-pp-vnet.ps1 -EnvironmentId <id>`.
3. Build connector flows by following the docs in [./connectors](./connectors/keyvault.md).
