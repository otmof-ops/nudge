# Contributing to nudge

Copyright (c) 2026 OFFTRACKMEDIA Studios (ABN: 84 290 819 896). All rights reserved.

| Field | Value |
|---|---|
| **Document ID** | OTM-NUDGE-CONTRIBUTING-001/2026 |
| **Authority** | OFFTRACKMEDIA Studios |
| **Version** | 1.0 |
| **Status** | Active |
| **Effective Date** | 2026-03-19 |

## Contributor License Agreement

By submitting a contribution to this repository (including but not limited to pull requests, patches, code, documentation, or any other materials), You represent, warrant, and agree to the following:

1. **Grant of Rights.** You hereby grant to OFFTRACKMEDIA Studios a perpetual, worldwide, non-exclusive, no-charge, royalty-free, irrevocable license to use, reproduce, modify, prepare derivative works of, publicly display, publicly perform, sublicense, and distribute Your contribution and any derivative works thereof, in any medium and for any purpose.

2. **Ownership Assignment.** To the maximum extent permitted by applicable law, You hereby irrevocably assign, transfer, and convey to OFFTRACKMEDIA Studios all right, title, and interest in and to Your contribution, including all Intellectual Property Rights therein. To the extent such assignment is not effective under applicable law, You grant OFFTRACKMEDIA Studios an exclusive, perpetual, irrevocable license as described in Section 1 above.

3. **Representations and Warranties.** You represent and warrant that: (a) You are the sole author of the contribution and have the legal right to grant the rights set forth herein; (b) the contribution is Your original work and does not infringe, misappropriate, or otherwise violate any Intellectual Property Rights or other rights of any third party; (c) the contribution does not contain any malicious code, viruses, or other harmful components; and (d) You are not subject to any agreement, obligation, or restriction that would prevent You from making the contribution or granting the rights described herein.

4. **No Obligation.** OFFTRACKMEDIA Studios is under no obligation to accept, merge, or use any contribution, and may reject contributions at its sole discretion.

5. **Indemnification.** You agree to indemnify and hold harmless OFFTRACKMEDIA Studios from any claims, damages, or liabilities arising from Your contribution, including any claim that Your contribution infringes a third party's Intellectual Property Rights.

## How to Contribute

1. Fork the repo and create a feature branch from `master`.
2. Follow existing code patterns and conventions (see below).
3. Run `make lint` and `make test` before submitting.
4. Run `shellcheck` on all `.sh` files — CI will enforce this.
5. Run `bash -n` syntax validation on all scripts.
6. Test on at least one supported desktop environment (KDE, GNOME, or XFCE).
7. Open a Pull Request using the provided [PR template](.github/PULL_REQUEST_TEMPLATE.md).

## Code Conventions

- **Shell dialect:** Bash (`#!/usr/bin/env bash`)
- **Strict mode:** All scripts must use `set -euo pipefail`
- **Linting:** All `.sh` files must pass `shellcheck` with zero warnings
- **Naming:** Variables use `UPPER_SNAKE_CASE`, functions use `lower_snake_case`
- **Comments:** Section dividers use `# --- Section Name ---`
- **Quoting:** Always double-quote variable expansions (`"$VAR"`, not `$VAR`)
- **Dependencies:** Prefer tools available in a standard Ubuntu/Debian install
- **Test files:** Use the BATS framework (`*.bats`)
- **Library modules:** Go in `lib/`. Tests go in `tests/test_<module>.bats`.

## Project Structure

```
nudge/
├── nudge.sh              — Thin dispatcher (~460 lines)
├── install.sh            — Interactive installer with upgrade support
├── uninstall.sh          — Full cleanup including systemd/completion/man
├── nudge.conf            — Configuration template (30 keys)
├── nudge.desktop         — XDG autostart entry
├── lib/                  — 10 library modules
│   ├── output.sh         — Exit codes, logging, JSON output
│   ├── config.sh         — Safe config parser, validation, migration
│   ├── lock.sh           — flock-based instance locking
│   ├── network.sh        — Multi-method network probe
│   ├── pkgmgr.sh         — apt/dnf/pacman/zypper + flatpak + snap
│   ├── notify.sh         — 5 notification backends
│   ├── schedule.sh       — Scheduling and deferral
│   ├── history.sh        — JSONL history log and viewer
│   ├── safety.sh         — Snapshots and reboot detection
│   └── selfupdate.sh     — GitHub release self-update
├── share/
│   ├── bash-completion/  — Bash tab completion
│   ├── man/              — Man page (nudge.1)
│   └── systemd/          — systemd user timer and service
├── tests/                — BATS test suite (11 files)
├── docs/                 — Governance files (CHANGELOG, ROADMAP, SAFETY, etc.)
├── EULA/                 — OFFTRACKMEDIA EULA v2.1-Software
├── .github/              — CI workflows, issue/PR templates, SECURITY.md
├── Makefile              — test/lint/install/uninstall
├── LICENSE               — Proprietary source-available license
└── (governance files)    — README, CHANGELOG, ROADMAP, SAFETY, SECURITY, etc.
```

---

## Commit Conventions

Commits MUST follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

### Types

| Type | When to Use | Example |
|------|------------|---------|
| `feat` | New feature, config key, backend | `feat(notify): add dunstify action support` |
| `fix` | Bug fix | `fix(config): handle missing config dir` |
| `docs` | Documentation or man page | `docs(man): document exit codes` |
| `style` | Formatting, whitespace | `style: normalize section dividers` |
| `refactor` | Code restructure without behavior change | `refactor(pkgmgr): extract lock check` |
| `test` | Adding or updating tests | `test(config): add enum validation tests` |
| `chore` | Build, deps, CI | `chore(ci): update actions/checkout to v6` |
| `ci` | CI/CD pipeline changes | `ci: add shellcheck job` |

Use the module name as the scope: `feat(notify)`, `fix(config)`, `test(schedule)`.

### Breaking Changes

Breaking changes MUST include a `BREAKING CHANGE:` footer and require a MAJOR version bump:

```
feat(config)!: rename DELAY to STARTUP_DELAY

BREAKING CHANGE: The DELAY config key has been renamed to STARTUP_DELAY.
Existing configs must be updated.
```

---

## Pull Request Process

### Before Opening a PR

- [ ] All tests pass locally (`make test`)
- [ ] Linter passes with zero warnings (`make lint`)
- [ ] `bash -n` syntax validation passes on all scripts
- [ ] Man page updated if commands, flags, or config keys changed
- [ ] `docs/CHANGELOG.md` updated under `[Unreleased]`

### PR Requirements

Every PR MUST:

- Have a clear title following Conventional Commits format
- Reference the related issue (`Closes #42`)
- Include tests for new features and bug fixes
- Pass all CI checks (ShellCheck, syntax, BATS)
- Have at least one approving review from a maintainer

---

## Reporting Issues

Found a bug or have a feature request?

1. Search existing issues to avoid duplicates.
2. Open a new issue at [GitHub Issues](https://github.com/otmof-ops/nudge/issues).
3. Include:
   - **Bug reports:** Steps to reproduce, expected behavior, actual behavior, distro, DE, notification backend, and `nudge --version` output.
   - **Feature requests:** Use case description, proposed interface, and why existing features cannot address the need.

---

## Security Vulnerabilities

**Do NOT open a public issue for security vulnerabilities.**

Report security issues via the process documented in [.github/SECURITY.md](../.github/SECURITY.md). We will respond within 48 hours and coordinate a fix and disclosure timeline with you.

---

(c) 2026 OFFTRACKMEDIA Studios · ABN 84 290 819 896
