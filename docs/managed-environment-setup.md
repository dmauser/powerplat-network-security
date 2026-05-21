# Managed Environment setup

This walkthrough explains how to prepare the Power Platform side of the lab before any Azure network injection steps run. The goal is to end with a United States environment that is managed, licensed correctly for the demo audience, and ready to be linked to `<enterprisePolicyArmId>` by `./scripts/02-configure-pp-vnet.ps1`.

## Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Create or select a United States environment](#create-or-select-a-united-states-environment)
- [Promote the environment to Managed Environment](#promote-the-environment-to-managed-environment)
- [Upgrade the governance tier to Standard](#upgrade-the-governance-tier-to-standard)
- [Bind Application Insights for telemetry](#bind-application-insights-for-telemetry)
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

## Upgrade the governance tier to Standard

Default Power Platform environments are created with `protectionLevel: Basic`. The VNet
injection operation (`NewNetworkInjection`) is blocked by the Power Platform control plane
until the governance tier is upgraded to **Standard**. If you skip this step, `./scripts/02-configure-pp-vnet.ps1` will attempt the upgrade automatically, but you can also perform it manually:

```powershell
Install-Module Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser -AllowClobber -Force
Import-Module Microsoft.PowerApps.Administration.PowerShell
Add-PowerAppsAccount

Set-AdminPowerAppEnvironmentGovernanceConfiguration `
    -EnvironmentName "<environmentId>" `
    -UpdatedGovernanceConfiguration @{ protectionLevel = "Standard" }
```

Wait approximately 60 seconds for the `EnableGovernanceConfiguration` lifecycle operation
to complete. You can verify the result in the [Power Platform admin center](https://admin.powerplatform.microsoft.com/)
under **Environments → Settings → Managed Environment**.

> **Note:** Attempting to upgrade the tier by PATCHing `scopes/admin/environments` directly returns 204 but makes no change. The dedicated governance configuration endpoint, called by `Set-AdminPowerAppEnvironmentGovernanceConfiguration`, is required. This is not documented in the standard VNet support setup guide ([learn.microsoft.com/power-platform/admin/vnet-support-setup-configure](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-setup-configure)) but is a confirmed prerequisite for environments starting at the Basic tier.

## Bind Application Insights for telemetry

After the ME is linked to the enterprise policy you can export Power Platform telemetry (Dataverse diagnostics, Power Automate flows, canvas app events) to Azure Application Insights. There is no public REST API for this step; it must be performed in the PPAC admin center.

> **Requirements:** Power Platform administrator role in the tenant **and** Dataverse System Administrator role on the environment. Managed Environments only.

1. Go to [Power Platform admin center](https://admin.powerplatform.microsoft.com/).
2. In the left navigation, select **Manage**.
3. Select **Data export**.
4. Open the **App Insights** tab.
5. Select **New data export**.
6. Give the export a friendly name (for example, `ppvnet-dev-export`).
7. Choose the data types to export (Dataverse diagnostics, Power Automate, and so on).
8. Select the environment: `<environmentId>`.
9. Under **Azure details**, select:
   - Subscription: `<subscriptionId>`
   - Resource group: `<resourceGroupName>`
   - Application Insights resource: `<appInsightsResourceName>`
10. Review the settings and select **Create**.

The export begins routing telemetry to App Insights within a few minutes. The connection string is resolved automatically from the resource picker; you do not need to paste the instrumentation key or connection string manually.

> **Note:** This path was verified against `learn.microsoft.com/power-platform/admin/set-up-export-application-insights` (updated 2026-01-05). Earlier documentation referenced a "Settings → Product → Features → Application Insights" toggle that no longer exists in current PPAC.

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

Use the enterprise policies module before you link the policy so you can verify the environment is in the expected geography. This manual validation is optional but useful; `./scripts/02-configure-pp-vnet.ps1` performs the same check before it calls `Enable-SubnetInjection`.

```powershell
Import-Module Microsoft.PowerPlatform.EnterprisePolicies
Get-EnvironmentRegion -EnvironmentId "<environmentId>"
```

Expected result for this lab:

- The returned geography or aligned region must map to the **United States** deployment shape.
- The paired Azure regions used by the lab must therefore be **eastus** and **westus**, as documented in [architecture.md](./architecture.md) and the [supported regions section](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview#supported-regions).

If the region does not map to the United States deployment, do not continue with the US deployment. Instead, either recreate the environment in the correct geography or build a different paired-region variant as outlined in [expansion-roadmap.md](./expansion-roadmap.md).

## Next step

After the environment is managed and the region is validated:

1. Run `./scripts/00-prereqs.sh` so the local toolchain is checked (`az` 2.60+, Bicep, PowerShell 7+, `jq`, and `bash`) and the required resource providers plus `enterprisePoliciesPreview` are registered.
2. Run `./scripts/01-deploy.sh` to deploy the Azure resources and produce `.azure/last-deploy-outputs.json` with `<enterprisePolicyArmId>`.
3. Run `./scripts/02-configure-pp-vnet.ps1 -EnvironmentId <environmentId>`. That script auto-installs the pinned `Microsoft.PowerPlatform.EnterprisePolicies` module version (0.17.0) if needed, validates the environment region again, and then either links the environment to `<enterprisePolicyArmId>` or exits cleanly if the same policy is already linked (making it safe to re-run).
4. Build connector flows by following the docs in [./connectors](./connectors/keyvault.md).
