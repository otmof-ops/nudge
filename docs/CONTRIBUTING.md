# Contributing to nudge

Fixes, new package managers, notification backends, docs and tests are all welcome.

## Licensing your contribution

nudge is BSD 3-Clause ([LICENSE](../LICENSE)); everything in the repository, documentation
included, is under it, and [REUSE.toml](../REUSE.toml) says so per path. A contribution is
accepted under the same license. To record that the work is yours to give, sign off each commit
(`git commit -s`): the `Signed-off-by` line is your statement, under the
[Developer Certificate of Origin](https://developercertificate.org), that you wrote it or have the
right to submit it under this license. You keep your copyright.

## How to Contribute

1. Fork the repo and create a feature branch from `main`.
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
├── nudge.sh              — Thin dispatcher; also the in-terminal upgrade runner (--_run-upgrade)
├── setup.sh              — Unified TUI: install, uninstall, configure, update, status
├── install.sh            — Wrapper → setup.sh --install
├── uninstall.sh          — Wrapper → setup.sh --uninstall
├── nudge.conf            — Configuration template (32 keys)
├── nudge.desktop         — XDG autostart entry
├── lib/                  — 16 library modules
│   ├── output.sh         — Exit codes, logging, JSON output
│   ├── config.sh         — Safe config parser, validation, migration
│   ├── lock.sh           — flock-based instance locking
│   ├── network.sh        — Multi-method network probe
│   ├── pkgmgr.sh         — apt/dnf/pacman/zypper + flatpak + snap, the upgrade session
│   ├── notify.sh         — 5 notification backends
│   ├── schedule.sh       — Scheduling and deferral
│   ├── history.sh        — JSONL history log and viewer
│   ├── safety.sh         — Snapshots and reboot detection
│   ├── selfupdate.sh     — GitHub release self-update
│   ├── errorreport.sh    — Crash reports and issue filing
│   ├── tui.sh            — TUI primitives
│   ├── select.sh         — The selection menu
│   ├── bunny-poses.sh    — The mascot: faces and poses
│   ├── bunny-dialogue.sh — The mascot: dialogue
│   └── bunny.sh          — The mascot: orchestration
├── share/
│   ├── bash-completion/  — Bash tab completion
│   ├── man/              — Man page (nudge.1)
│   └── systemd/          — systemd user timer and service
├── tests/                — BATS test suite (17 files)
├── docs/                 — CHANGELOG, ROADMAP, SAFETY, STANDARDS, ADRs
├── .github/              — CI workflows, issue/PR templates, SECURITY.md
├── Makefile              — test/lint/install/uninstall
├── LICENSE               — BSD 3-Clause
├── LICENSES/             — The license text, REUSE layout
└── REUSE.toml            — One license for the whole tree
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
- Carry a `Signed-off-by` line on every commit (`git commit -s`)
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
