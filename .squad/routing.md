# Routing

How the Coordinator picks an agent for incoming work.

## By signal

| Signal / keyword | Route to | Notes |
|------------------|----------|-------|
| `infra/`, Bicep, `*.bicep`, parameter files, `az deployment`, `bicep-validate` workflow | Trinity | Infra/IaC owner |
| Architecture, topology, peering, DNS zones, private endpoints, subnet sizing, region choice | Morpheus | Reviewer gate on infra/integration changes |
| `Enable-SubnetInjection`, enterprise policy linking, Managed Environment, `scripts/02-configure-pp-vnet.ps1`, `Microsoft.PowerPlatform.EnterprisePolicies` | Tank | Power Platform ops |
| `scripts/00-prereqs.sh`, resource provider registration, PowerShell module installs | Tank | Prereqs / ops |
| `scripts/03-validate-network.sh`, DNS resolution tests, connector smoke tests, demo-script accuracy | Neo | Validation |
| `docs/connectors/*`, README, `docs/architecture.md`, `docs/deployment-guide.md`, `docs/troubleshooting.md`, `docs/cost-control.md`, `docs/security-notes.md`, `docs/expansion-roadmap.md` | Niobe | Docs (collaborates with Tank/Neo for technical content) |
| `docs/managed-environment-setup.md` | Tank → Niobe | Tank owns the steps; Niobe owns prose |
| `docs/demo-script.md` | Neo → Niobe | Neo owns test steps; Niobe owns prose |
| `archive/**` | (read-only) | Do not edit unless user explicitly asks |
| `.github/workflows/bicep-validate.yml` | Trinity | CI for Bicep |
| Cost / SKU questions | Morpheus + Niobe | Architecture + docs |
| Security posture (publicNetworkAccess, RBAC, AAD-only auth) | Morpheus | Reviewer |

## Reviewer gates

- **Infra changes** (`infra/**`, Bicep modules) → reviewed by Morpheus.
- **Power Platform integration changes** (`scripts/02-*.ps1`, enterprise policy shape) → reviewed by Morpheus.
- **Connector docs** → reviewed by Neo for technical accuracy.
- **Validation script changes** → reviewed by Morpheus for what *should* happen.

## Multi-agent patterns

- "Add a new connector" → Trinity (any infra), Tank (any PP wiring), Neo (test plan), Niobe (connector doc) — parallel.
- "Update architecture diagram" → Morpheus decides, Niobe renders Mermaid.
- "Deployment broken" → Trinity (Bicep), Tank (PP scripts), Neo (validation) in parallel; Morpheus synthesizes.
