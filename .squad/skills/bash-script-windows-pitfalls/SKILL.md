# Skill: Bash Script Windows Pitfalls

**Pattern:** Known bash-on-Windows failure modes that cause silent or confusing errors in this repo's shell scripts. Each entry has: symptom, root cause, and the minimal fix.

## Use cases

- Diagnosing `syntax error near unexpected token` on scripts that look correct
- Fixing `03-validate-network.sh` (or any future `.sh`) that fails only on Windows Git Bash
- Writing new bash scripts that embed PowerShell commands

---

## Pitfall 1 — CRLF line endings in `.sh` files

**Symptom:** `bash: syntax error near unexpected token '{'` or `bash: $'\r': command not found` when running a script via Git Bash on Windows.

**Root cause:** Git cloned the file with CRLF line endings. Some versions of Git Bash mis-parse carriage returns embedded in function definitions or command substitutions.

**Diagnosis:**
```bash
file scripts/03-validate-network.sh
# Output: "...with CRLF, LF line terminators" → problem confirmed
```

**Fix (one-time strip):**
```bash
sed -i 's/\r//' scripts/03-validate-network.sh
```

**Fix (permanent — repo-level):**
Add `.gitattributes` at repo root:
```
*.sh text eol=lf
```
Then re-stage: `git add --renormalize .`

---

## Pitfall 2 — PowerShell `{ }` braces inside bash `$(...)` command substitution

**Symptom:** `bash: line N: syntax error near unexpected token '{'` inside a function that embeds a PowerShell `-Command` argument with `if (...) { ... } else { ... }`.

**Root cause:** Inside `$(...)`, bash parses `{` preceded by `)` or whitespace as the start of a brace group command. Escaped double-quotes (`\"...\"`inside the substitution do not suppress this brace interpretation.

**Failing pattern:**
```bash
result="$(pwsh -Command \"if (\$x) { 'True' } else { 'False' }\" | tr -d '\r')"
#                                            ^--- bash sees this { as brace group start
```

**Fix — use `$'...'` quoting to pass the PowerShell command:**
```bash
local ps_cmd=$'$x = Test-Something; if ($x) { "True" } else { "False" }'
result="$(pwsh -NoLogo -NoProfile -Command "$ps_cmd" | tr -d '\r')"
```

**Fix — assign to variable first, then pass:**
```bash
local ps_cmd
ps_cmd='$result = Test-NetConnection -ComputerName '"'"'host'"'"' -Port 1433; if ($result.TcpTestSucceeded) { "True" } else { "False" }'
result="$(pwsh -NoLogo -NoProfile -Command "$ps_cmd" | tr -d '\r')"
```

---

## Pitfall 3 — Azure Key Vault returns HTTP 401 (not 403) for unauthenticated public-denial probes

**Symptom:** Validation script asserts `HTTP 403` from a bare `curl` to Key Vault, but gets `HTTP 401`.

**Root cause:** Azure Key Vault evaluates authentication before the network ACL for unauthenticated requests. An unauthenticated request from a public IP triggers the auth layer first (`AKV10000: missing Bearer token` → 401) even when `publicNetworkAccess=Disabled`. An **authenticated** request from a public IP correctly returns `403 ForbiddenByConnection`.

**Evidence of correct lock-down (authenticated path):**
```bash
az keyvault secret list --vault-name "$kv_name" 2>&1
# Returns: ERROR: (Forbidden) ForbiddenByConnection
```

**Correct bash probe for KV public-access denial:**
```bash
kv_deny_output="$(az keyvault secret list --vault-name "$kv_name" 2>&1 || true)"
if echo "$kv_deny_output" | grep -q 'ForbiddenByConnection'; then
  ok 'Key Vault public endpoint: ForbiddenByConnection as expected'
else
  fail "Key Vault public endpoint did not return ForbiddenByConnection: ${kv_deny_output}"
  return 1
fi
```

**Why not just accept 401?** HTTP 401 from an unauthenticated probe does NOT prove the firewall is active — it only proves the auth layer is responding. A misconfigured KV with `publicNetworkAccess=Enabled` would also return 401 to an unauthenticated request. The authenticated probe is the only reliable test.

---

## Quick diagnosis checklist for `03-validate-network.sh` failures

1. `syntax error near unexpected token '{'` → Check CRLF (Pitfall 1) AND brace-in-`$()` issue (Pitfall 2)
2. `KV public REST endpoint: expected HTTP 403, got 401` → Unauthenticated probe (Pitfall 3) — use authenticated az CLI check
3. `SQL Server resource ID: value was empty` → SQL was skipped (`deploySqlSkipped=true`); not a failure, deferred per Option B
4. `Could not retrieve a storage account key` → Operator may lack `Storage Account Contributor` or key access may be disabled; check `allowSharedKeyAccess` on storage account

## Examples in this repo

- `scripts/03-validate-network.sh` — contains all three pitfalls (as of Phase 2 validation, 2026-05-21)
- `.squad/decisions/inbox/neo-phase2-validation-2026-05-20.md` — full evidence table from Phase 2 validation
