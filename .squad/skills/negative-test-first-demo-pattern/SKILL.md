# SKILL: negative-test-first pattern for private-endpoint demos

**Domain:** Power Platform connector demos, private endpoint validation
**Author:** Tank — 2026-05-21

## Pattern

When demoing a private-endpoint–protected resource via a Power Platform connector, always execute and screenshot the **negative test first**, before granting any RBAC or wiring up the connector.

## Why

1. The negative test requires zero setup — it works immediately because the public path is already closed.
2. Capturing `ForbiddenByConnection` before the positive test creates a clear before/after story for the audience.
3. If RBAC is granted first and public access is accidentally re-enabled later (e.g., during troubleshooting), the negative test loses its proof value.
4. The error message itself (`ForbiddenByConnection`, `PublicNetworkAccess is set to Disabled`) is self-explanatory to a non-technical audience.

## Steps

1. From presenter's laptop (public internet, no VNet path), run:
   ```bash
   az keyvault secret show --vault-name <kv> --name <secret>
   ```
2. Screenshot the `ForbiddenByConnection` error.
3. Then grant RBAC to the demo user.
4. Run the positive test (Power App or flow).
5. Show telemetry evidence (`CallerIPAddress_s` = private IP in `AzureDiagnostics`).

## Applied in

- `docs/demos/keyvault-demo.md` — Parts 1, 2, 3
