# Copilot Instructions — powerbi-network-security

## Repository status

This repo now centers on documentation for a **Power Platform VNet support demo lab**. The previous Fabric Managed Private Endpoint → Azure SQL → Power BI demo remains in [`archive/`](../archive) as read-only reference. Do not edit or extend files in `archive/` unless explicitly asked.

## Architecture overview

The active lab documents a United States Power Platform geography mapped to paired Azure regions **eastus** and **westus**. The documented design uses two VNets with delegated `snet-pp-delegated` subnets, private endpoints for Key Vault, Azure SQL Database, and Storage, private DNS zones linked to both VNets, a `Microsoft.PowerPlatform/enterprisePolicies` resource with `kind=NetworkInjection`, and a Managed Environment linked through `Enable-SubnetInjection`.

Documentation lives under [`docs/`](../docs), with connector-specific walkthroughs in [`docs/connectors/`](../docs/connectors). Start with `docs/architecture.md`, `docs/managed-environment-setup.md`, and `docs/deployment-guide.md`.

## Repository conventions

- New active content lives at the repo root; `archive/` is read-only unless explicitly requested.
- Prefer pure GitHub-flavored Markdown; do not use HTML in docs.
- Each doc should start with a short summary paragraph, then a contents list, then the main body.
- Use ATX headings (`#`, `##`, `###`).
- Use fenced code blocks with language tags such as `bash`, `powershell`, `bicep`, and `mermaid`.
- Cross-link aggressively with relative paths like `./connectors/keyvault.md`.
- Use deploy-output placeholders such as `<keyVaultName>` and `<enterprisePolicyArmId>` instead of hard-coded tenant values.
- Cite Microsoft Learn sources inline when documenting product behavior or prerequisites.

## Verification commands

There is no repo-wide build or lint workflow yet for the new lab content. For documentation changes, verify relative Markdown links and basic repo state.

- Relative link check: run the PowerShell scan used during authoring against `docs\**\*.md`
- Git status: `git --no-pager status --short`
