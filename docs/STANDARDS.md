# nudge — Repository Standards

| Field | Value |
|---|---|
| **Document ID** | OTM-NUDGE-STD-001/2026 |
| **Authority** | OFFTRACKMEDIA Studios (ABN 84 290 819 896) |
| **Document Owner** | Jay @ OFFTRACKMEDIA Studios |
| **Version** | 1.0 |
| **Status** | Active |
| **Classification** | Internal |
| **Effective Date** | 2026-03-19 |
| **Next Review Date** | 2026-09-19 |
| **Supersedes** | N/A (Initial Release) |

## Document Version History

| Version | Date | Author | Summary of Changes | Sections Affected |
|---------|------|--------|-------------------|-------------------|
| 1.0 | 2026-03-19 | Jay | Initial release — v2.0.0 standards | All |

**Scope:** 70 files · 18 shell scripts · 15 test files · 17 documentation files · 31 configuration keys

This document is the single source of truth for all structural, coding, testing, and governance decisions in the nudge repository. Every contributor, automated pipeline, and maintenance task MUST conform to these rules. No exception is valid unless documented as an explicit override in [Appendix C — Exception Registry](#appendix-c--exception-registry).

---

## Normative Language

The key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT, RECOMMENDED, MAY, and OPTIONAL in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

| Keyword | Meaning |
|---------|---------|
| **MUST** / **REQUIRED** / **SHALL** | Absolute requirement |
| **MUST NOT** / **SHALL NOT** | Absolute prohibition |
| **SHOULD** / **RECOMMENDED** | Strong preference — deviation requires documented justification |
| **SHOULD NOT** / **NOT RECOMMENDED** | Strong preference against — permissible only with justification |
| **MAY** / **OPTIONAL** | Truly optional — no justification needed |

---

<!-- MACHINE-READABLE CONFIGURATION
     Linting and generation tools should import these values rather than parsing prose.
     Update corresponding prose rules when changing values here. -->

```yaml
cli_standards_config:
  schema_version: "1.0"
  effective_date: "2026-03-19"
  review_due: "2026-09-19"
  binary_name: "nudge"
  env_prefix: "NUDGE"
  command_naming:
    case: "kebab-case"
    max_length: 32
    reserved_names: ["help", "version"]
  flags:
    long_prefix: "--"
    short_prefix: "-"
    reserved_short_flags: ["h", "v"]
  exit_codes:
    success: 0
    general_error: 1
    usage_error: 2
    reserved_start: 3
    max_assigned: 13
  output:
    default_format: "text"
    json_flag: "--json"
    color_disable_env: "NO_COLOR"
  versioning:
    scheme: "semver"
    tag_prefix: "v"
  testing:
    framework: "bats-core"
    min_test_count: 150
```

---

## Roles and Responsibilities

| Activity | Responsible | Accountable | Consulted | Informed |
|----------|------------|-------------|-----------|----------|
| Shell module development | Contributor | Maintainer | Reviewers | Team |
| Config key additions | Contributor | Jay | Maintainer | All |
| Exit code assignments | Maintainer | Jay | Contributor | All |
| Notification backend additions | Contributor | Maintainer | Reviewers | All |
| Package manager support | Contributor | Maintainer | Reviewers | All |
| Man page authorship | Contributor | Maintainer | — | — |
| Release decisions | Maintainer | Jay | Contributors | All |
| Updating this document | Maintainer | Jay | Contributors | All |

---

## Table of Contents

1. [Repository Structure](#1-repository-structure)
2. [Shell Coding Standards](#2-shell-coding-standards)
3. [Module Architecture](#3-module-architecture)
4. [Configuration System](#4-configuration-system)
5. [Exit Code Standards](#5-exit-code-standards)
6. [Notification Backend Standards](#6-notification-backend-standards)
7. [Package Manager Abstraction](#7-package-manager-abstraction)
8. [Testing Standards](#8-testing-standards)
9. [CI/CD Pipeline](#9-cicd-pipeline)
10. [Versioning and Release](#10-versioning-and-release)
11. [Documentation Standards](#11-documentation-standards)
12. [Security Standards](#12-security-standards)
13. [Governance File Standards](#13-governance-file-standards)
14. [Quality Gates](#14-quality-gates)

---

## 1. Repository Structure

### 1.1 Canonical Directory Layout

The repository has 6 top-level directories (`lib/`, `share/`, `tests/`, `docs/`, `EULA/`, `.github/`). No new top-level directories may be created without updating this file.

```
nudge/
├── lib/                    # Shell library modules (14 files)
├── share/                  # Distributable ancillary files
│   ├── bash-completion/    # Tab completion script
│   ├── man/                # Man page (troff)
│   └── systemd/            # systemd user timer and service
├── tests/                  # BATS test suite (15 files)
├── docs/                   # Governance and project documentation
│   └── adr/                # Architecture Decision Records
├── EULA/                   # Legal — OFFTRACKMEDIA EULA v2.1-Software
├── .github/                # CI, templates, security policy
│   ├── ISSUE_TEMPLATE/     # Bug report + feature request (YAML forms)
│   ├── workflows/          # validate-pr.yml + release.yml
│   ├── SECURITY.md         # Vulnerability disclosure policy
│   ├── PULL_REQUEST_TEMPLATE.md
│   ├── dependabot.yml
│   └── FUNDING.yml
└── (root)                  # Core scripts, config, README, LICENSE only
```

### 1.2 Root File Inventory

The root must contain only core product files. Governance files belong in `docs/`.

| File | Location | Purpose |
|------|----------|---------|
| `nudge.sh` | root | Main dispatcher script |
| `setup.sh` | root | Unified TUI — install, uninstall, configure, update, status |
| `install.sh` | root | Thin wrapper → delegates to `setup.sh --install` |
| `uninstall.sh` | root | Thin wrapper → delegates to `setup.sh --uninstall` |
| `nudge.conf` | root | Configuration template (31 keys) |
| `nudge.desktop` | root | XDG autostart desktop entry |
| `Makefile` | root | Build targets: test, lint, install, uninstall |
| `LICENSE` | root | Proprietary source-available license notice |
| `NOTICE.txt` | root | Legal notice file |
| `README.md` | root | Project documentation |
| `.editorconfig` | root | Editor formatting rules |
| `.gitignore` | root | Git exclusion rules |
| `.gitattributes` | root | Line ending and binary rules |
| `CHANGELOG.md` | `docs/` | Release history (Keep a Changelog format) |
| `ROADMAP.md` | `docs/` | Feature roadmap + deliberately out of scope |
| `SAFETY.md` | `docs/` | System modification risk documentation |
| `CONTRIBUTING.md` | `docs/` | Contributor license agreement + conventions |
| `CREDITS-AND-COMMUNITY.md` | `docs/` | Attribution and IP framework |
| `CODE_OF_CONDUCT.md` | `docs/` | Community standards |
| `STANDARDS.md` | `docs/` | This file |
| `ascii-art.md` | `docs/` | ASCII art sheet and branding guide |
| `guide.md` | `docs/` | User guide and walkthrough |
| `RISK-ASSESSMENTS.md` | `docs/` | Risk assessment documentation |
| `adr/001–005` | `docs/adr/` | Architecture Decision Records (5 files) |
| `SECURITY.md` | `.github/` | Vulnerability disclosure policy |

### 1.3 File Naming Convention

All file names use the following rules:

- **Shell scripts:** `lowercase.sh` — no hyphens in script names that are installed to `$PATH`
- **Library modules:** `lowercase.sh` in `lib/` — single-word names matching the subsystem
- **Test files:** `test_<module>.bats` in `tests/` — underscore separator, matching the module name
- **Configuration:** `nudge.conf` — single canonical name
- **Governance files:** `UPPERCASE.md` at root — GitHub convention for discoverability
- **Ancillary files:** lowercase in `share/` — matching the install destination name
- **systemd units:** `nudge.service`, `nudge.timer` — matching the unit name
- **Desktop entry:** `nudge.desktop` — matching the application name

### 1.4 No File Sprawl Rule

Ancillary files (man pages, completion scripts, systemd units) must never be placed at the repository root. They belong in `share/` under the subdirectory that mirrors their install destination:

| File Type | Repository Path | Install Destination |
|-----------|----------------|---------------------|
| Bash completion | `share/bash-completion/nudge` | `~/.local/share/bash-completion/completions/nudge` |
| Man page | `share/man/nudge.1` | `~/.local/share/man/man1/nudge.1` |
| systemd timer | `share/systemd/nudge.timer` | `~/.config/systemd/user/nudge.timer` |
| systemd service | `share/systemd/nudge.service` | `~/.config/systemd/user/nudge.service` |

---

## 2. Shell Coding Standards

### 2.1 Dialect and Strict Mode

All shell scripts must use Bash and enable strict mode:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

No exceptions. No `#!/bin/sh`. No omitting `pipefail`.

### 2.2 Variable Naming

| Context | Convention | Example |
|---------|-----------|---------|
| Global/config variables | `UPPER_SNAKE_CASE` | `NETWORK_HOST`, `LOG_LEVEL` |
| Local variables inside functions | `lower_snake_case` with `local` | `local result`, `local line_num` |
| Internal/private globals | Leading underscore + `UPPER_SNAKE_CASE` | `_JSON_MODE`, `_NUDGE_START_TIME` |
| Constants | `readonly UPPER_SNAKE_CASE` | `readonly EXIT_OK=0` |
| Associative arrays | `declare -gA UPPER_SNAKE_CASE` | `declare -gA CONFIG_DEFAULTS` |
| Loop variables | `lower_snake_case` | `for opt in "${opts[@]}"` |

### 2.3 Quoting

Always double-quote variable expansions. No exceptions.

```bash
# Correct
echo "$VARIABLE"
if [[ -n "$VALUE" ]]; then

# Wrong
echo $VARIABLE
if [[ -n $VALUE ]]; then
```

The only exception is inside `$(( ))` arithmetic expressions where quoting is not required.

### 2.4 Function Naming

Functions use `lower_snake_case`. Module functions are prefixed with the module name:

| Module | Function Prefix | Example |
|--------|----------------|---------|
| `output.sh` | `log_`, `json_`, `output_`, `exit_` | `log_info`, `json_emit`, `output_init` |
| `config.sh` | `config_` | `config_load`, `config_validate` |
| `lock.sh` | `lock_` | `lock_acquire`, `lock_release` |
| `network.sh` | `network_` | `network_check`, `network_probe_once` |
| `pkgmgr.sh` | `pkgmgr_`, `flatpak_`, `snap_` | `pkgmgr_count_updates`, `flatpak_count` |
| `notify.sh` | `notify_`, `_prompt_`, `_show_preview_` | `notify_detect`, `notify_prompt` |
| `schedule.sh` | `schedule_`, `parse_` | `schedule_due`, `parse_duration` |
| `history.sh` | `history_` | `history_write`, `history_show` |
| `safety.sh` | `safety_` | `safety_reboot_check`, `safety_snapshot` |
| `selfupdate.sh` | `selfupdate_`, `version_` | `selfupdate_check`, `version_gt` |
| `tui.sh` | `_tui_` | `_tui_init`, `_tui_bunny`, `_tui_menu` |
| `bunny-poses.sh` | `bunny_pose`, `_bunny_pose_` | `bunny_pose`, `_bunny_pose_sitting` |
| `bunny-dialogue.sh` | `_BUNNY_MSG_`, `_bunny_pick_`, `_bunny_load_`, `_bunny_save_` | `_bunny_pick_message`, `_bunny_load_last_message` |
| `bunny.sh` | `bunny_`, `_bunny_` | `bunny_face`, `bunny_message`, `bunny_render`, `bunny_init` |

Private helper functions within a module use a leading underscore: `_classify_priority`, `_detect_terminal`, `_build_upgrade_cmd`.

### 2.5 Section Dividers

Use the following format for section dividers within scripts:

```bash
# --- Section Name ---
```

Three hyphens, space, section name, space, three hyphens. Consistent across all files.

### 2.6 Shellcheck Compliance

All `.sh` files must pass `shellcheck` with zero errors and zero warnings. Info and style notices are acceptable.

Permitted `shellcheck disable` directives (documented here — do not add new ones without updating this list):

| Directive | File | Reason |
|-----------|------|--------|
| `SC2034` | `lib/output.sh` | Exit code constants are used by sourcing scripts |
| `SC2034` | `setup.sh` | Variables are used by sourcing scripts |
| `SC2034` | `lib/bunny.sh` | Face constants are used by sourcing scripts |
| `SC2317` | `nudge.sh` | `_cleanup()` is invoked via `trap`, not directly |
| `SC2206` | `setup.sh` | Word splitting on config key strings is intentional |
| `SC2178` | `lib/bunny-dialogue.sh` | Array variable reassignment is intentional |
| `SC1003` | `lib/output.sh` | Backslash-quote in sed pattern is intentional |
| `SC2012` | `lib/safety.sh` | `ls -t /boot/vmlinuz-*` is safe for kernel file listing |

### 2.7 No `source` for User-Supplied Files

Configuration files must never be loaded via `source` or `.` (dot-source). The config parser in `lib/config.sh` uses a line-by-line parser with type validation. This is a security requirement — see Section 12.

### 2.8 Error Handling

- Functions that can fail must return a meaningful exit code
- Callers must check return codes: `if ! some_function; then handle_error; fi`
- Never use `|| true` to suppress meaningful errors — only for cleanup operations where failure is non-fatal
- `set -e` is active — unhandled failures terminate the script

### 2.9 Dependencies

All external commands used by nudge must be documented:

| Command | Required | Used By | Fallback |
|---------|----------|---------|----------|
| `bash` (4.0+) | Yes | All scripts | None — hard requirement |
| `flock` | Yes | `lib/lock.sh` | None — part of util-linux |
| `date` | Yes | Multiple modules | None — coreutils |
| `curl` | No | `lib/network.sh`, `lib/selfupdate.sh` | `wget`, then `ping` |
| `wget` | No | `lib/network.sh`, `lib/selfupdate.sh` | `curl`, then `ping` |
| `ping` | No | `lib/network.sh` | `curl`, `wget` |
| `apt` | No | `lib/pkgmgr.sh` | Other package managers |
| `dnf` | No | `lib/pkgmgr.sh` | Other package managers |
| `pacman` | No | `lib/pkgmgr.sh` | Other package managers |
| `zypper` | No | `lib/pkgmgr.sh` | Other package managers |
| `flatpak` | No | `lib/pkgmgr.sh` | Disabled if absent |
| `snap` | No | `lib/pkgmgr.sh` | Disabled if absent |
| `kdialog` | No | `lib/notify.sh` | Other backends |
| `zenity` | No | `lib/notify.sh` | Other backends |
| `dunstify` | No | `lib/notify.sh` | Other backends |
| `gdbus` | No | `lib/notify.sh` | Other backends |
| `notify-send` | No | `lib/notify.sh` | Other backends |
| `timeshift` | No | `lib/safety.sh` | `snapper`, `btrfs` |
| `snapper` | No | `lib/safety.sh` | `timeshift`, `btrfs` |
| `whiptail` | No | `setup.sh` (TUI) | `dialog`, then numbered-list fallback |
| `dialog` | No | `setup.sh` (TUI) | `whiptail`, then numbered-list fallback |
| `shellcheck` | Dev only | CI/lint | Required for contribution |
| `bats` | Dev only | `make test` | Required for contribution |

No new required dependencies may be added without updating this table and the CREDITS-AND-COMMUNITY.md tool attribution table.

---

## 3. Module Architecture

### 3.1 Dispatcher Pattern

`nudge.sh` is a thin dispatcher (~440 lines) that:

1. Locates and sources all 14 library modules from `lib/`
2. Parses CLI arguments
3. Loads and validates configuration
4. Handles utility commands (`--version`, `--help`, `--history`, `--config`, `--validate`, `--migrate`, `--defer`, `--self-update`)
5. Executes the main pipeline: lock → schedule guard → delay → network → detect pkgmgr → count updates → prompt → action → history → exit

The dispatcher must not contain subsystem logic. All subsystem logic belongs in `lib/` modules.

### 3.2 Module Inventory

Exactly 14 library modules exist. No new modules may be created without updating this file.

| Module | Responsibility | Dependencies |
|--------|---------------|-------------|
| `output.sh` | Exit codes, log levels, JSON output, content rendering | None |
| `config.sh` | Load, validate, migrate config | `output.sh` |
| `lock.sh` | flock-based instance locking | `output.sh` |
| `network.sh` | Multi-method connectivity probe | `output.sh`, `bunny.sh` |
| `pkgmgr.sh` | Package manager abstraction + flatpak + snap | `output.sh`, `config.sh` |
| `notify.sh` | 5 notification backends + preview + deferral UI | `output.sh`, `config.sh`, `bunny.sh` |
| `schedule.sh` | Scheduling, interval guards, deferral | `output.sh` |
| `history.sh` | JSONL history log + viewer | `output.sh` |
| `safety.sh` | Reboot detection + pre-upgrade snapshots | `output.sh`, `notify.sh` |
| `selfupdate.sh` | GitHub release check + self-install | `output.sh` |
| `tui.sh` | TUI rendering primitives — bunny, menus, input, colors | `output.sh`, `bunny.sh` |
| `bunny-poses.sh` | 10 ASCII art pose functions | `bunny.sh` (face constants) |
| `bunny-dialogue.sh` | 14+ dialogue arrays, random picker, no-repeat logic | None |
| `bunny.sh` | Bunny orchestrator — render, season, context, state, faces, streak | `config.sh`, `bunny-poses.sh`, `bunny-dialogue.sh` |

### 3.3 Module Source Order

Modules must be sourced in dependency order in `nudge.sh`:

```bash
source "$NUDGE_LIB_DIR/output.sh"          # 1. No dependencies
source "$NUDGE_LIB_DIR/config.sh"           # 2. Depends on output
source "$NUDGE_LIB_DIR/lock.sh"             # 3. Depends on output
source "$NUDGE_LIB_DIR/network.sh"          # 4. Depends on output
source "$NUDGE_LIB_DIR/pkgmgr.sh"          # 5. Depends on output, config
source "$NUDGE_LIB_DIR/notify.sh"           # 6. Depends on output, config
source "$NUDGE_LIB_DIR/schedule.sh"         # 7. Depends on output
source "$NUDGE_LIB_DIR/history.sh"          # 8. Depends on output
source "$NUDGE_LIB_DIR/safety.sh"           # 9. Depends on output, notify
source "$NUDGE_LIB_DIR/selfupdate.sh"       # 10. Depends on output
source "$NUDGE_LIB_DIR/tui.sh"              # 11. Depends on output
source "$NUDGE_LIB_DIR/bunny-poses.sh"      # 12. Depends on bunny face constants
source "$NUDGE_LIB_DIR/bunny-dialogue.sh"   # 13. No dependencies
source "$NUDGE_LIB_DIR/bunny.sh"            # 14. Depends on config, bunny-poses, bunny-dialogue
```

### 3.4 Module Interface Rules

- Every module must be independently sourceable for testing (with stub dependencies)
- No module may modify global state belonging to another module
- Inter-module communication uses global variables with documented ownership
- No module may call `exit` — only the dispatcher (`nudge.sh`) calls `exit`
- Exception: `lock_acquire` returns 1 on failure; the dispatcher decides to exit

### 3.5 Global Variable Ownership

| Variable | Owner Module | Set By | Read By |
|----------|-------------|--------|---------|
| `EXIT_*` constants | `output.sh` | Module load | All modules, dispatcher |
| `_JSON_MODE`, `_VERBOSE_MODE` | `output.sh` | `output_init()` | `_log()`, `json_emit()` |
| `_JSON_DATA` | `output.sh` | `json_set()` | `json_emit()` |
| `CONFIG_DEFAULTS`, `CONFIG_TYPES` | `config.sh` | Module load | `config_load()`, `config_validate()` |
| All 31 config keys | `config.sh` | `config_load()` | All modules |
| `LOCK_FD`, `LOCK_FILE` | `lock.sh` | `lock_acquire()` | `lock_release()` |
| `DETECTED_PKGMGR` | `pkgmgr.sh` | `detect_pkgmgr()` | All pkgmgr functions |
| `PKG_UPDATES_*` | `pkgmgr.sh` | `pkgmgr_count_updates()` | Dispatcher, notify, history |
| `PKG_UPDATE_LIST` | `pkgmgr.sh` | `pkgmgr_list_updates()` | Preview, JSON |
| `NOTIFY_BACKEND` | `notify.sh` | `notify_detect()` | All notify functions |
| `NOTIFY_RESPONSE` | `notify.sh` | `notify_prompt()` | Dispatcher |
| `HISTORY_FILE` | `history.sh` | Module load | `history_write()`, `history_show()` |
| `CLEANUP_PIDS` | Dispatcher | Dispatcher | `_cleanup()` |
| `BUNNY_STREAK_FILE` | `bunny.sh` | Module load | `bunny_get_streak()`, `bunny_increment_streak()`, `bunny_reset_streak()` |
| `BUNNY_FACE_*` constants | `bunny.sh` | Module load (readonly) | `bunny_face()`, `bunny_pose()` |
| `_BUNNY_INSTALL_DATE_FILE` | `bunny.sh` | Module load / `bunny_init()` | `_bunny_detect_special_context()`, `_bunny_detect_season()` |
| `_BUNNY_LAST_SEEN_FILE` | `bunny.sh` | Module load / `bunny_init()` | `_bunny_detect_special_context()` |
| `_BUNNY_MSG_*` arrays | `bunny-dialogue.sh` | Module load | `_bunny_pick_message()`, `_bunny_message_disney()` |

---

## 4. Configuration System

### 4.1 Config File Location

| Version | Path | Status |
|---------|------|--------|
| v2.0+ | `~/.config/nudge/nudge.conf` | Current |
| v1.x (legacy) | `~/.config/nudge.conf` | Supported via auto-migration |

The config directory `~/.config/nudge/` is the canonical location. The legacy path is checked only as a migration fallback.

### 4.2 Config Key Registry

Every configuration key must be registered in three places:

1. `CONFIG_DEFAULTS` associative array in `lib/config.sh` — defines the default value
2. `CONFIG_TYPES` associative array in `lib/config.sh` — defines the type constraint
3. `nudge.conf` template at repository root — documented with comments

A key that exists in one location but not the other two is a standards violation.

### 4.3 Type System

| Type | Constraint | Example |
|------|-----------|---------|
| `bool` | Must be `true` or `false` | `ENABLED=true` |
| `int` | Must match `^[0-9]+$` | `DELAY=45` |
| `enum:a,b,c` | Must be one of the listed values | `SCHEDULE_MODE` ∈ `{login,daily,weekly}` |
| `string` | No constraint (all values valid) | `UPDATE_COMMAND="sudo apt update"` |

### 4.4 Adding a New Config Key

To add a new configuration key:

1. Add the key with its default value to `CONFIG_DEFAULTS` in `lib/config.sh`
2. Add the key with its type constraint to `CONFIG_TYPES` in `lib/config.sh`
3. Add the key with documentation to `nudge.conf` template
4. Add the key to the Configuration section of `README.md`
5. Add the key to the man page (`share/man/nudge.1`)
6. Add the key to tab completion in `share/bash-completion/nudge` (if the `--config` completer lists keys)
7. Update this file's config key count in the header
8. Write a test case in `tests/test_config.bats` verifying the default and validation

All 8 steps must be completed in the same commit. A partially registered key is a standards violation.

### 4.5 Config Migration

When the config format changes between versions, a migration function must be added to `lib/config.sh`:

- Migration functions are named `migrate_<from>_to_<to>()` (e.g., `migrate_110_to_200()`)
- Migrations must back up the existing config before modifying it
- Migrations must preserve all existing user values
- New keys are added with their defaults — never overwrite a user's existing value
- The `CONF_VERSION` key tracks the config format version

---

## 5. Exit Code Standards

### 5.1 Assigned Exit Codes

nudge uses 14 named exit codes. These are defined as `readonly` constants in `lib/output.sh` and must not be changed without a major version bump.

| Code | Constant | Meaning | Scriptable |
|------|----------|---------|------------|
| 0 | `EXIT_OK` | No updates available or completed successfully | Yes |
| 1 | `EXIT_UPDATES_DECLINED` | User chose "Not Now" | Yes |
| 2 | `EXIT_UPDATES_APPLIED` | Updates ran successfully | Yes |
| 3 | `EXIT_UPDATES_FAILED` | Update command returned non-zero | Yes |
| 4 | `EXIT_DISABLED` | `ENABLED=false` in config | Yes |
| 5 | `EXIT_NETWORK_FAIL` | Network check failed after all retries | Yes |
| 6 | `EXIT_PKG_LOCK` | Package manager lock held by another process | Yes |
| 7 | `EXIT_ALREADY_RUNNING` | Another nudge instance is running (flock) | Yes |
| 8 | `EXIT_NO_BACKEND` | No notification backend available | Yes |
| 9 | `EXIT_DEFERRED` | User chose "Remind me later" | Yes |
| 10 | `EXIT_CONFIG_ERROR` | Config validation failed fatally | Yes |
| 11 | `EXIT_INTERRUPTED` | Caught SIGINT, SIGTERM, or SIGHUP | Yes |
| 12 | `EXIT_SNAPSHOT_FAILED` | Pre-upgrade snapshot failed, upgrade aborted | Yes |
| 13 | `EXIT_REBOOT_PENDING` | Reboot required from previous upgrade | Yes |

### 5.2 Exit Code Rules

- Exit codes 0–13 are reserved. Codes 14–125 are available for future use.
- Codes 126–255 are reserved by POSIX and must not be used.
- Every exit path in `nudge.sh` must use a named constant, never a raw integer.
- The `EXIT_REASONS` associative array must contain a string mapping for every exit code.
- Exit codes must be documented in the man page, README, and this file.

---

## 6. Notification Backend Standards

### 6.1 Detection Order

When `NOTIFICATION_BACKEND=auto`, backends are detected in this order:

1. `dunstify` — full action support, tiling WM native
2. `kdialog` — full dialog support, KDE native
3. `zenity` — full dialog support, GNOME/GTK native
4. `gdbus` — D-Bus notifications, passive
5. `notify-send` — desktop notifications, passive (no interactive prompt)
6. `none` — no backend available → exit `EXIT_NO_BACKEND`

This order must not be changed without updating STANDARDS.md, README.md, and the man page.

### 6.2 Backend Capability Matrix

| Backend | Interactive Prompt | Defer Button | Auto-Dismiss | Preview |
|---------|-------------------|-------------|--------------|---------|
| `dunstify` | Yes (actions) | Yes | Yes (timeout) | Body text (5 lines) |
| `kdialog` | Yes (yesnocancel) | Yes | Yes (timeout cmd) | Textbox then dialog |
| `zenity` | Yes (question) | Yes (extra-button) | Yes (native) | Text-info then question |
| `gdbus` | Passive | No | Yes (timeout) | Body text |
| `notify-send` | Passive | No | N/A | Body text |

### 6.3 Adding a New Backend

To add a new notification backend:

1. Add `_prompt_<backend>()` function in `lib/notify.sh`
2. Add the backend to `notify_detect()` in the correct detection order position
3. Add the backend to `NOTIFICATION_BACKEND` enum in `CONFIG_TYPES`
4. Update the capability matrix in this file
5. Update the backend table in `README.md`
6. Update the bug report template dropdown
7. Update the man page
8. Write integration tests verifying detection

---

## 7. Package Manager Abstraction

### 7.1 Supported Package Managers

| Manager | Distribution | Detection Method |
|---------|-------------|-----------------|
| `apt` | Debian, Ubuntu, Mint | `command -v apt` + `/var/lib/dpkg` exists |
| `dnf` | Fedora, RHEL, CentOS | `command -v dnf` |
| `pacman` | Arch, Manjaro, EndeavourOS | `command -v pacman` |
| `zypper` | openSUSE Leap, Tumbleweed | `command -v zypper` |

Detection order: `apt` → `dnf` → `pacman` → `zypper`. First match wins. Override with `PKGMGR_OVERRIDE`.

### 7.2 Required Interface

Every package manager backend must implement these functions:

| Function | Purpose | Returns |
|----------|---------|---------|
| Lock check | Test if package manager lock is held | 0 (free) or 1 (locked) |
| Count updates | Return total + security update counts | Sets `PKG_UPDATES_TOTAL`, `PKG_UPDATES_SECURITY` |
| List updates | Return structured package list | Sets `PKG_UPDATE_LIST` (name\|from\|to\|priority) |
| Upgrade | Run upgrade in detected terminal | Exit code of upgrade command |
| Check held | Return held/pinned packages | stdout |

### 7.3 Priority Classification

Packages are classified into 4 tiers based on name pattern matching:

| Priority | Packages | Pattern |
|----------|----------|---------|
| `CRITICAL` | Kernel, OpenSSL, glibc, OpenSSH, sudo, PAM, systemd (+ lib variants) | `^(linux-image\|linux-headers\|openssl\|libssl\|glibc\|libc6\|openssh\|sudo\|pam\|libpam\|systemd)(-\|$)` |
| `SECURITY` | Any package flagged by distro security tools | Distro-specific detection |
| `RECOMMENDED` | Major version bumps | (reserved for future implementation) |
| `STANDARD` | Everything else | Default classification |

### 7.4 Adding a New Package Manager

To add a new package manager backend:

1. Add detection logic in `detect_pkgmgr()` in `lib/pkgmgr.sh`
2. Implement all 5 interface functions for the new backend
3. Add a lock check method for the new manager
4. Add the manager to `PKGMGR_OVERRIDE` documentation
5. Update the bug report template distribution dropdown
6. Update the feature request template package manager dropdown
7. Update `install.sh` to detect and set appropriate `UPDATE_COMMAND`
8. Update `SAFETY.md` with distribution-specific risks
9. Update `CREDITS-AND-COMMUNITY.md` tool attribution table
10. Write test cases in `tests/test_pkgmgr.bats`

---

## 8. Testing Standards

### 8.1 Framework

All tests use [bats-core](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

### 8.2 Test File Inventory

Every library module must have a corresponding test file. The test file naming convention is `test_<module>.bats`.

| Test File | Module Under Test | Minimum Test Count |
|-----------|------------------|-------------------|
| `test_output.bats` | `lib/output.sh` | 19 |
| `test_config.bats` | `lib/config.sh` | 15 |
| `test_lock.bats` | `lib/lock.sh` | 4 |
| `test_network.bats` | `lib/network.sh` | 8 |
| `test_pkgmgr.bats` | `lib/pkgmgr.sh` | 21 |
| `test_notify.bats` | `lib/notify.sh` | 23 |
| `test_history.bats` | `lib/history.sh` | 9 |
| `test_schedule.bats` | `lib/schedule.sh` | 14 |
| `test_safety.bats` | `lib/safety.sh` | 8 |
| `test_selfupdate.bats` | `lib/selfupdate.sh` | 13 |
| `test_integration.bats` | `nudge.sh` (end-to-end) | 18 |
| `test_setup.bats` | `setup.sh` + `lib/tui.sh` | 24 |
| `test_bunny.bats` | `lib/bunny.sh` | 64 |
| `test_bunny_poses.bats` | `lib/bunny-poses.sh` | 28 |

| `test_bunny_dialogue.bats` | `lib/bunny-dialogue.sh` | 37 |

**Current total: 309 tests. This number must not decrease.**

### 8.3 Test Structure

Every test file follows this structure:

```bash
#!/usr/bin/env bats

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    TMPDIR_TEST=$(mktemp -d)
    # Stub logging functions
    log_debug() { :; }
    log_info()  { :; }
    log_warn()  { :; }
    log_error() { :; }
    # Source the module under test
    source "$PROJECT_DIR/lib/<module>.sh"
}

teardown() {
    rm -rf "$TMPDIR_TEST"
}

@test "descriptive test name" {
    # Arrange → Act → Assert
}
```

### 8.4 Test Rules

- Tests must not require network access
- Tests must not require root/sudo
- Tests must not require a running desktop environment
- Tests must not modify files outside `$TMPDIR_TEST`
- Tests must clean up after themselves in `teardown()`
- Mock binaries are placed in a temp `PATH` directory, never system-wide
- Associative arrays from modules require `declare -gA` to be visible in BATS test functions
- Use `run` + `[[ "$status" -ne 0 ]]` instead of `! function_call` for negation tests (BATS compatibility)

### 8.5 Test Coverage Requirements

When adding a new feature:

- New config keys must have validation tests (valid + invalid values)
- New functions must have at least one positive and one negative test
- New CLI flags must have an integration test in `test_integration.bats`
- Edge cases (empty input, missing files, invalid data) must be tested

---

## 9. CI/CD Pipeline

### 9.1 Pull Request Validation (`validate-pr.yml`)

Runs on every pull request targeting `master`. Two jobs:

**Job 1 — ShellCheck & Syntax:**
- `shellcheck nudge.sh install.sh uninstall.sh setup.sh lib/*.sh`
- `bash -n` syntax validation on all scripts and lib modules
- `bash -n nudge.conf` — config template must be valid bash syntax

**Job 2 — BATS Test Suite:**
- `bats tests/`
- All 297 tests must pass

Both jobs must pass before a PR can be merged.

### 9.2 Release Workflow (`release.yml`)

Triggered by pushing a tag matching `v*`. Creates a GitHub Release with:

- All core scripts and config files
- All library modules
- All ancillary files from `share/`
- Auto-generated release notes

### 9.3 Dependabot

Configured for `github-actions` ecosystem. Weekly checks on Monday. Commit prefix: `ci`. Labels: `dependencies`, `ci`.

### 9.4 CI Rules

- CI must use `actions/checkout@v6` (current at time of writing — update via Dependabot)
- CI runs on `ubuntu-latest` — the primary target platform
- No CI job may take longer than 5 minutes
- CI failures block merge — no override without documented justification

---

## 10. Versioning and Release

### 10.1 Versioning Scheme

nudge uses [Semantic Versioning 2.0.0](https://semver.org/):

- **MAJOR** — breaking changes to config format, exit codes, CLI flags, or module API
- **MINOR** — new features, new config keys, new backends, new package managers
- **PATCH** — bug fixes, documentation updates, CI improvements

### 10.2 Version Locations

The version string must be updated in all of the following locations for every release:

| Location | Format | Example |
|----------|--------|---------|
| `nudge.sh` line 6 | `NUDGE_VERSION="X.Y.Z"` | `NUDGE_VERSION="2.0.0"` |
| `install.sh` line 6 | `VERSION="X.Y.Z"` | `VERSION="2.0.0"` |
| `CHANGELOG.md` | `## [X.Y.Z] — YYYY-MM-DD` | `## [2.0.0] — 2026-03-19` |
| `SECURITY.md` version table | `X.Y.x \| Yes` | `2.0.x \| Yes` |
| `share/man/nudge.1` header | `.TH NUDGE 1 "Month Year" "nudge X.Y.Z"` | `"nudge 2.0.0"` |

### 10.3 Release Process

1. Update version in all locations listed in 10.2
2. Update `CHANGELOG.md` with all changes since last release
3. Commit: `release: nudge vX.Y.Z`
4. Tag: `git tag vX.Y.Z`
5. Push: `git push origin master --tags`
6. Release workflow creates GitHub Release automatically

### 10.4 Breaking Change Policy

Changes to the following are breaking and require a MAJOR version bump:

- Removing or renaming a config key
- Changing the meaning or default of an existing config key
- Changing an exit code number or meaning
- Removing or renaming a CLI flag
- Changing the config file path
- Removing a notification backend or package manager

---

## 11. Documentation Standards

### 11.1 README Structure

The `README.md` must contain these sections in this order:

1. Badges (ShellCheck, Release, License, Tests, Language, Distros)
2. One-line description
3. Why nudge? (comparison table vs competitors)
4. Features (emoji-bullet scannable highlights)
5. Quick Start (one-liner install + git clone)
6. How It Works (pipeline diagram)
7. Architecture (module table)
8. Supported Distributions (table)
9. Notification Backends (capability matrix)
10. Requirements
11. Install (interactive, quick, unattended, upgrade, flags table, installed files table)
12. Uninstall (flags table)
13. Configuration (grouped by category, full key table)
14. CLI Flags (with examples)
15. Exit Codes (full table)
16. JSON Output (example)
17. Scheduling
18. Screenshots (visual previews of notification flow and TUI)
19. Development (make test, make lint, man page)
20. Troubleshooting
21. Safety
22. Security
23. Contributing
24. Project Stats (test count, module count, social proof metrics)
25. Project (links to governance files)
26. License

### 11.2 CHANGELOG Format

Follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format:

- Sections: Added, Changed, Fixed, Removed
- Entries are bullet points, not paragraphs
- Most recent version first
- Comparison links at bottom: `[X.Y.Z]: https://github.com/otmof-ops/nudge/compare/...`

### 11.3 Man Page Requirements

The man page (`share/man/nudge.1`) must contain these sections:

NAME, SYNOPSIS, DESCRIPTION, OPTIONS (all CLI flags), CONFIGURATION (all 30 keys with types and defaults), EXIT CODES (all 14), FILES (all installed paths), ENVIRONMENT (XDG vars, DISPLAY, DBUS), EXAMPLES (10+), SEE ALSO, BUGS, AUTHORS, COPYRIGHT.

---

## 12. Security Standards

### 12.1 Config Injection Prevention

The config parser in `lib/config.sh` uses `printf -v` for variable assignment — never `eval`, `source`, or `declare -g "$key=$value"` with unvalidated input. This prevents arbitrary code execution via crafted config values.

### 12.2 No Secrets in Repository

The following must never be committed:

- API keys, tokens, or credentials
- Personal paths (e.g., `/home/username/`)
- Email addresses other than the official OTM contact
- Private keys or certificates

### 12.3 Network Security

- All GitHub API requests use HTTPS
- Self-update downloads verify SHA256 checksums when available
- No data is transmitted to OTM servers — nudge has no telemetry
- Network connectivity checks use standard HTTP HEAD requests or ICMP ping

### 12.4 Privilege Model

- nudge installs entirely in user-space (`~/.local/`)
- Only the configured `UPDATE_COMMAND` runs with `sudo`
- The user is prompted by the system for their password — nudge never stores or handles credentials
- flock operates on a user-owned file in `$XDG_RUNTIME_DIR`

---

## 13. Governance File Standards

### 13.1 Required Governance Files

Every governance file listed in Section 1.2 must:

- Contain the copyright notice: `(c) 2026 OFFTRACKMEDIA Studios · ABN 84 290 819 896`
- Be updated for the current version when a release changes relevant content
- Use GitHub-compatible markdown (CommonMark)

### 13.2 SECURITY.md Requirements

- Must list currently supported versions
- Must include a vulnerability reporting email with response SLA
- Must define in-scope and out-of-scope vulnerability classes
- Must document the security design principles

### 13.3 SAFETY.md Requirements

- Must cover all supported package managers (not just apt)
- Must cover Flatpak and Snap risks
- Must cover snapshot tool risks
- Must document what nudge does NOT do (negative scope)
- Must include user responsibility section

### 13.4 CONTRIBUTING.md Requirements

- Must contain a Contributor License Agreement with IP assignment clause
- Must list the current project structure
- Must reference `make lint` and `make test`
- Must list code conventions

---

## 14. Quality Gates

### 14.1 Pre-Commit Checklist

Before every commit, verify:

- [ ] `bash -n` passes on all `.sh` files
- [ ] `shellcheck` returns zero errors and zero warnings on all `.sh` files
- [ ] `bats tests/` — all 309 tests pass
- [ ] No `TODO`, `FIXME`, or `HACK` comments introduced without a tracking issue
- [ ] No hardcoded personal paths
- [ ] Version string updated if this is a release commit

### 14.2 Pre-Release Checklist

Before every release:

- [ ] All pre-commit checks pass
- [ ] Version updated in all 5 locations (Section 10.2)
- [ ] CHANGELOG.md updated with all changes
- [ ] README.md reflects current feature set
- [ ] Man page reflects current flags and config keys
- [ ] `nudge --version` prints correct version
- [ ] `nudge --validate` passes with defaults
- [ ] `nudge --config` prints all config keys
- [ ] `nudge --help` shows all flags
- [ ] `install.sh --version` prints correct version
- [ ] `install.sh --help` shows all flags
- [ ] `uninstall.sh --help` shows all flags

### 14.3 Structural Audit Triggers

A full structural audit of STANDARDS.md compliance is triggered when:

- A new library module is proposed
- A new notification backend is added
- A new package manager is supported
- More than 5 config keys are added in a single release
- The CI pipeline is restructured

---

## Appendix C — Exception Registry

All documented exceptions to the rules in this standard. Every exception MUST be approved by the document owner and MUST include a justification and review date.

| # | Rule | Exception | Justification | Approved By | Review Date |
|---|------|-----------|--------------|------------|-------------|
| 1 | §1.3 File Naming | `test_<module>.bats` uses underscore separator | BATS community convention; consistent with upstream examples | Jay | 2026-09-19 |
| 2 | §2.6 ShellCheck | SC2034 disabled in `lib/output.sh` | Exit code constants are used by sourcing scripts, not directly | Jay | 2026-09-19 |
| 3 | §2.6 ShellCheck | SC2317 disabled in `nudge.sh` | `_cleanup()` is invoked via `trap`, not directly | Jay | 2026-09-19 |
| 4 | §2.6 ShellCheck | SC2088 disabled in `uninstall.sh` | Tilde in display strings is intentional (not path expansion) | Jay | 2026-09-19 |
| 5 | §2.6 ShellCheck | SC2012 disabled in `lib/safety.sh` | `ls -t /boot/vmlinuz-*` is safe for kernel file listing | Jay | 2026-09-19 |
| 6 | §1.3 File Naming | `lib/bunny-dialogue.sh` uses hyphenated name | Module name established in v2.0.0; renaming would break all import references | Jay | 2026-09-19 |
| 7 | §1.3 File Naming | `lib/bunny-poses.sh` uses hyphenated name | Module name established in v2.0.0; renaming would break all import references | Jay | 2026-09-19 |
| 8 | §5.2 Exit Codes | `nudge.sh` line 25 uses raw `exit 10` | Pre-source bootstrap guard — EXIT_CONFIG_ERROR constant not yet available | Jay | 2026-09-19 |

---

## Appendix A — File Type Inventory

| Extension | Count | Purpose |
|-----------|-------|---------|
| `.sh` | 18 | Shell scripts (1 dispatcher + 14 lib + 1 setup + 2 wrappers) |
| `.bats` | 15 | BATS test files |
| `.md` | 22 | Markdown documentation + governance + ADRs |
| `.yml` | 7 | GitHub Actions workflows + issue templates + dependabot + config + funding |
| `.conf` | 1 | Configuration template |
| `.desktop` | 1 | XDG autostart entry |
| `.service` | 1 | systemd user service unit |
| `.timer` | 1 | systemd user timer unit |
| `.1` | 1 | troff man page |
| `.bash` | 0 | Bash completion (installed as `nudge` without extension) |
| `.txt` | 2 | EULA text + NOTICE |
| (no ext) | 3 | Makefile, LICENSE, bash completion |
| **Total** | **75** | |

## Appendix B — Configuration Key Reference

All 31 configuration keys with types and defaults. This table is authoritative — it must match `CONFIG_DEFAULTS` and `CONFIG_TYPES` in `lib/config.sh` exactly.

| # | Key | Type | Default | Category |
|---|-----|------|---------|----------|
| 1 | `CONF_VERSION` | string | `2.0.0` | System |
| 2 | `ENABLED` | bool | `true` | Core |
| 3 | `DELAY` | int | `45` | Core |
| 4 | `CHECK_SECURITY` | bool | `true` | Core |
| 5 | `AUTO_DISMISS` | int | `0` | Core |
| 6 | `UPDATE_COMMAND` | string | `sudo apt update && sudo apt full-upgrade` | Core |
| 7 | `NETWORK_HOST` | string | `archive.ubuntu.com` | Network |
| 8 | `NETWORK_TIMEOUT` | int | `5` | Network |
| 9 | `NETWORK_RETRIES` | int | `2` | Network |
| 10 | `OFFLINE_MODE` | enum:skip,notify,queue | `skip` | Network |
| 11 | `NOTIFICATION_BACKEND` | enum:auto,kdialog,zenity,notify-send,dunstify,gdbus,none | `auto` | Notification |
| 12 | `DUNST_APPNAME` | string | `nudge` | Notification |
| 13 | `PREVIEW_UPDATES` | bool | `true` | Notification |
| 14 | `SECURITY_PRIORITY` | bool | `true` | Notification |
| 15 | `SCHEDULE_MODE` | enum:login,daily,weekly | `login` | Schedule |
| 16 | `SCHEDULE_INTERVAL_HOURS` | int | `24` | Schedule |
| 17 | `DEFERRAL_OPTIONS` | string | `1h,4h,1d` | Schedule |
| 18 | `PKGMGR_OVERRIDE` | string | *(empty)* | Package Manager |
| 19 | `FLATPAK_ENABLED` | enum:true,false,auto | `auto` | Package Manager |
| 20 | `SNAP_ENABLED` | enum:true,false,auto | `auto` | Package Manager |
| 21 | `HISTORY_ENABLED` | bool | `true` | History |
| 22 | `HISTORY_MAX_LINES` | int | `500` | History |
| 23 | `LOG_FILE` | string | *(empty)* | Logging |
| 24 | `LOG_LEVEL` | enum:debug,info,warn,error | `info` | Logging |
| 25 | `JSON_OUTPUT` | bool | `false` | Logging |
| 26 | `REBOOT_CHECK` | bool | `true` | Safety |
| 27 | `SNAPSHOT_ENABLED` | bool | `false` | Safety |
| 28 | `SNAPSHOT_TOOL` | enum:auto,timeshift,snapper,btrfs | `auto` | Safety |
| 29 | `SELF_UPDATE_CHECK` | bool | `true` | Self-Update |
| 30 | `SELF_UPDATE_CHANNEL` | enum:stable,beta | `stable` | Self-Update |
| 31 | `BUNNY_PERSONALITY` | enum:classic,disney | `disney` | Personality |

**Note:** `CONF_VERSION` is system-managed and documented with "do not edit" in the config template. It is included in the 30-key count.

---

(c) 2026 OFFTRACKMEDIA Studios · ABN 84 290 819 896
