# nudge

```text
    (\__/)
    (='.'=)  ~ a gentle nudge to keep your system fresh ~
    (")_(")
```

[![ShellCheck](https://github.com/otmof-ops/nudge/actions/workflows/validate-pr.yml/badge.svg)](https://github.com/otmof-ops/nudge/actions/workflows/validate-pr.yml)
[![Latest Release](https://img.shields.io/github/v/release/otmof-ops/nudge?label=release)](https://github.com/otmof-ops/nudge/releases)
[![License](https://img.shields.io/badge/license-Proprietary-red)](EULA/OFFTRACKMEDIA_EULA_2025.txt)
[![Tests](https://img.shields.io/badge/tests-332%20passing-brightgreen)](tests/)
[![Language](https://img.shields.io/badge/language-bash-blue)](nudge.sh)
[![Distros](https://img.shields.io/badge/distros-4%20supported-blue)](docs/STANDARDS.md)

**A gentle nudge to keep your system fresh.**

Lightweight Linux desktop update manager that checks for available packages after login and asks if you'd like to update. Supports multiple distributions and package managers (apt, dnf, pacman, zypper), 5 notification backends, Flatpak and Snap stores, scheduling with deferral, pre-upgrade snapshots, and a friendly bunny mascot. Pure bash. Zero compiled dependencies. 332 tests.

## Beta Testing

nudge is in active development and publicly available for early adopters. If you're running a Linux desktop and want to help improve it, install it, use it, and report what breaks. Bug reports, edge cases, quirky distro behaviour, notification backends not cooperating — all of it is useful.

**How to help:**

1. Install nudge on your daily driver (see [Quick Start](#quick-start))
2. Use it normally — let it run at login, try the different notification backends, test scheduling and deferral
3. File issues at [github.com/otmof-ops/nudge/issues](https://github.com/otmof-ops/nudge/issues) with your distro, desktop environment, and what happened vs what you expected

The more variety of setups it gets tested on, the faster it stabilises. Every bug report helps.

## Why nudge?

Most Linux update tools are either silent and automatic, locked to one desktop environment, or require heavyweight runtimes. nudge is a lightweight system update notification tool that asks before acting — a consent-first Linux update manager built for every desktop.

| Feature | nudge | unattended-upgrades | GNOME Software | topgrade |
|---------|-------|--------------------|--------------------|----------|
| Asks before updating | **Yes** | No (auto) | Yes | No (runs all) |
| Multi-distro | **4 pkg mgrs** | Debian only | GNOME only | Multi |
| Flatpak + Snap | **Yes** | No | Partial | Yes |
| Lightweight (pure bash) | **Yes** | Yes | No | No (Rust) |
| Notification backends | **5** | 0 | 1 | 0 |
| Scheduling + deferral | **Yes** | Yes | No | No |
| Pre-upgrade snapshots | **Yes** | No | No | No |
| Test suite | **332** | — | — | — |

## Features

- **Consent-first updates** — never updates without your explicit approval; Update Now, Remind Later, or Not Now
- **Multi-distro support** — auto-detects apt, dnf, pacman, and zypper across Ubuntu, Fedora, Arch, and openSUSE
- **5 notification backends** — dunstify, kdialog, zenity, gdbus, and notify-send with automatic detection
- **Flatpak + Snap** — checks universal package stores alongside your system package manager
- **Scheduling and deferral** — login, daily, or weekly checks with customizable "remind me later" intervals
- **Pre-upgrade snapshots** — optional timeshift, snapper, or btrfs snapshots before every update
- **Security priority classification** — highlights critical and security updates (kernel, openssl, glibc, sudo)
- **Friendly mascot** — the Nudge Bunny with 10 ASCII poses and 100+ rotating dialogue lines
- **JSON output** — structured output for scripting, waybar/polybar integration, and automation
- **JSONL history** — searchable update history with date filtering
- **Zero telemetry** — no data collection, no phone-home, fully auditable source
- **User-space install** — everything lives in `~/.local/`, no root persistence, no daemon

## Quick Start

**One-liner install:**

```bash
bash <(curl -sL https://raw.githubusercontent.com/otmof-ops/nudge/main/setup.sh) --install --defaults
```

**Or clone and run the setup TUI:**

```bash
git clone https://github.com/otmof-ops/nudge.git
cd nudge
./setup.sh
```

That's it. nudge will notify you at next login when updates are available.

## How It Works

```
Login/Timer → nudge.sh → load config → acquire lock → schedule guard → delay →
network probe (curl/wget/ping) → detect package manager → lock check →
count updates (system + flatpak + snap) → if 0: exit → build preview with
priority classification → show dialog → "Update Now": snapshot → upgrade →
reboot check | "Remind Later": defer → write duration | "Not Now": exit →
write history → exit with named code
```

## Architecture

nudge v2.0.0 uses a modular library design — the main script is a ~480-line dispatcher that sources 15 modules from `lib/`:

| Module | Purpose |
|--------|---------|
| `lib/output.sh` | Exit codes, logging, JSON output, content rendering |
| `lib/config.sh` | Safe config parser, validation, migration |
| `lib/lock.sh` | flock-based instance locking |
| `lib/network.sh` | Multi-method network probe (curl/wget/ping) |
| `lib/pkgmgr.sh` | apt/dnf/pacman/zypper + flatpak + snap |
| `lib/notify.sh` | dunstify/kdialog/zenity/gdbus/notify-send backends |
| `lib/schedule.sh` | Scheduling, interval guards, deferral |
| `lib/history.sh` | JSONL history log and viewer |
| `lib/safety.sh` | Pre-upgrade snapshots, reboot detection |
| `lib/selfupdate.sh` | GitHub release self-update check |
| `lib/errorreport.sh` | Crash reports and automated GitHub issue filing |
| `lib/tui.sh` | TUI rendering primitives — bunny, menus, colors |
| `lib/bunny-poses.sh` | 10 ASCII art pose functions |
| `lib/bunny-dialogue.sh` | 100+ rotating dialogue messages, random picker |
| `lib/bunny.sh` | Bunny orchestrator — render, season, context, state |

## Supported Distributions

| Distribution | Package Manager | Status |
|-------------|----------------|--------|
| Ubuntu / Debian | `apt` | Full support |
| Fedora / RHEL | `dnf` | Full support |
| Arch Linux | `pacman` | Full support |
| openSUSE | `zypper` | Full support |
| Any (Flatpak) | `flatpak` | Auto-detected |
| Any (Snap) | `snap` | Auto-detected |

## Notification Backends

| Backend | Interactive | Defer | Auto-Dismiss | Detection Order |
|---------|------------|-------|--------------|-----------------|
| `dunstify` | Yes (actions) | Yes | Yes | 1st |
| `kdialog` | Yes (dialog) | Yes | Yes (timeout) | 2nd |
| `zenity` | Yes (dialog) | Yes | Yes (native) | 3rd |
| `gdbus` | Passive | No | Yes | 4th |
| `notify-send` | Passive | No | N/A | 5th |

## Requirements

- Linux desktop with one of: apt, dnf, pacman, or zypper
- One of: dunstify, kdialog, zenity, gdbus, or notify-send
- A terminal emulator (konsole, gnome-terminal, xfce4-terminal, or xterm)
- Optional: flatpak, snap, timeshift/snapper (for snapshots)

## Install

### Interactive Setup (Recommended)

```bash
git clone git@github.com:otmof-ops/nudge.git
cd nudge
./setup.sh
```

The unified TUI walks you through install, configure, update, and uninstall — all guided by the Nudge Bunny.

### Quick Install (defaults)

```bash
./setup.sh --install --defaults
```

### Scripted / Unattended Install

```bash
./setup.sh --install --unattended
```

### One-Liner from GitHub

```bash
bash <(curl -sL https://raw.githubusercontent.com/otmof-ops/nudge/main/setup.sh) --install --defaults
```

### Upgrade from v1.x

```bash
./setup.sh --install --upgrade
```

Preserves your existing config, runs migration to add new keys with defaults.

### Setup Options

| Flag | Description |
|------|-------------|
| `--install` | Install nudge |
| `--uninstall` | Uninstall nudge |
| `--update` | Check and install updates |
| `--config-only` | Open configure flow only |
| `--defaults` | Skip prompts, use default settings |
| `--unattended` | Non-interactive install (implies `--defaults`) |
| `--upgrade` | In-place upgrade, preserve config |
| `--systemd` | Use systemd user timer for autostart |
| `--xdg` | Use XDG autostart entry |
| `--no-color` | Disable colored output |
| `--prefix=PATH` | Custom install prefix (default: `$HOME`) |
| `--dry-run` | Show what would happen, change nothing |
| `--keep-config` | Uninstall: preserve config directory |
| `--check` | Update: just check, print version, exit |

Legacy `install.sh` and `uninstall.sh` wrappers are still supported for backward compatibility.

### Installed Files

| File | Purpose |
|------|---------|
| `~/.local/bin/nudge.sh` | Main dispatcher script |
| `~/.local/lib/nudge/*.sh` | Library modules (14) |
| `~/.config/nudge/nudge.conf` | Configuration (31 keys) |
| `~/.config/autostart/nudge.desktop` | XDG autostart entry |
| `~/.config/systemd/user/nudge.timer` | systemd timer (if selected) |
| `~/.config/systemd/user/nudge.service` | systemd service (if selected) |
| `~/.local/share/bash-completion/completions/nudge` | Bash completion |
| `~/.local/share/man/man1/nudge.1` | Man page |
| `~/.local/share/nudge/` | History, state, deferral files |

## Uninstall

```bash
./setup.sh --uninstall
```

Or via the TUI: run `./setup.sh` and choose option 2.

Shows what will be removed and asks for confirmation. Cleans up systemd timer, bash completion, man page, history, and state files.

| Flag | Description |
|------|-------------|
| `--yes`, `-y` | Skip confirmation prompts |
| `--keep-config` | Preserve `~/.config/nudge/` |
| `--no-color` | Disable colored output |

## Configuration

Edit `~/.config/nudge/nudge.conf`:

### Core Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ENABLED` | bool | `true` | Enable or disable nudge |
| `DELAY` | int | `45` | Seconds to wait after login |
| `CHECK_SECURITY` | bool | `true` | Highlight security updates |
| `AUTO_DISMISS` | int | `0` | Auto-dismiss dialog (seconds, 0 = never) |
| `UPDATE_COMMAND` | string | `sudo apt update && sudo apt full-upgrade` | Update command |

### Network Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `NETWORK_HOST` | string | `archive.ubuntu.com` | Connectivity check host |
| `NETWORK_TIMEOUT` | int | `5` | Check timeout (seconds) |
| `NETWORK_RETRIES` | int | `2` | Retry count |
| `OFFLINE_MODE` | enum | `skip` | `skip` / `notify` / `queue` |

### Notification Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `NOTIFICATION_BACKEND` | enum | `auto` | `auto`/`kdialog`/`zenity`/`dunstify`/`gdbus`/`notify-send`/`none` |
| `DUNST_APPNAME` | string | `nudge` | App name for dunst |
| `PREVIEW_UPDATES` | bool | `true` | Show package list before prompting |
| `SECURITY_PRIORITY` | bool | `true` | Show critical/security packages first |

### Schedule Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `SCHEDULE_MODE` | enum | `login` | `login` / `daily` / `weekly` |
| `SCHEDULE_INTERVAL_HOURS` | int | `24` | Hours between checks |
| `DEFERRAL_OPTIONS` | string | `1h,4h,1d` | "Remind me later" choices |

### Package Manager Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `PKGMGR_OVERRIDE` | string | *(empty)* | Force specific package manager |
| `FLATPAK_ENABLED` | enum | `auto` | `true` / `false` / `auto` |
| `SNAP_ENABLED` | enum | `auto` | `true` / `false` / `auto` |

### History & Logging

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `HISTORY_ENABLED` | bool | `true` | Write history records |
| `HISTORY_MAX_LINES` | int | `500` | Rotate history at this count |
| `LOG_FILE` | string | *(empty)* | Log file path (empty = none) |
| `LOG_LEVEL` | enum | `info` | `debug` / `info` / `warn` / `error` |
| `JSON_OUTPUT` | bool | `false` | Default to JSON output |

### Safety Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `REBOOT_CHECK` | bool | `true` | Detect reboot needed post-upgrade |
| `SNAPSHOT_ENABLED` | bool | `false` | Snapshot before upgrade |
| `SNAPSHOT_TOOL` | enum | `auto` | `auto` / `timeshift` / `snapper` / `btrfs` |

### Self-Update Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `SELF_UPDATE_CHECK` | bool | `true` | Check for newer nudge version |
| `SELF_UPDATE_CHANNEL` | enum | `stable` | `stable` / `beta` |

### Personality Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `BUNNY_PERSONALITY` | enum | `disney` | `classic` (neutral) / `disney` (Thumper baby voice) |

## CLI Flags

```bash
nudge --version              # Print version
nudge --help                 # Show help
nudge --dry-run              # Run checks, no dialogs
nudge --check-only           # Print update count
nudge --check-only --json    # JSON output
nudge --verbose              # Verbose logging
nudge --history              # Show last 20 history records
nudge --history 50           # Show last 50 records
nudge --history --json       # Raw JSONL dump
nudge --history --since DATE # Filter by date
nudge --defer 4h             # Defer next check
nudge --self-update          # Download latest version
nudge --config               # Print resolved config
nudge --validate             # Validate config
nudge --report               # Show crash reports
nudge --report --file        # File latest crash as GitHub issue
nudge --report --clear       # Clear all crash reports
nudge --migrate              # Run config migration
```

## Exit Codes

| Code | Constant | Meaning |
|------|----------|---------|
| 0 | `EXIT_OK` | No updates / completed |
| 1 | `EXIT_UPDATES_DECLINED` | User said "Not Now" |
| 2 | `EXIT_UPDATES_APPLIED` | Updates ran successfully |
| 3 | `EXIT_UPDATES_FAILED` | Update command failed |
| 4 | `EXIT_DISABLED` | ENABLED=false |
| 5 | `EXIT_NETWORK_FAIL` | Network check failed |
| 6 | `EXIT_PKG_LOCK` | Package manager locked |
| 7 | `EXIT_ALREADY_RUNNING` | Another instance running |
| 8 | `EXIT_NO_BACKEND` | No notification backend |
| 9 | `EXIT_DEFERRED` | User chose "Remind later" |
| 10 | `EXIT_CONFIG_ERROR` | Config validation failed |
| 11 | `EXIT_INTERRUPTED` | SIGINT/SIGTERM/SIGHUP |
| 12 | `EXIT_SNAPSHOT_FAILED` | Snapshot failed, aborted |
| 13 | `EXIT_REBOOT_PENDING` | Reboot required |

## JSON Output

With `--json`, nudge emits a single JSON object:

```json
{
  "nudge_version": "2.0.0",
  "timestamp": "2026-03-19T09:15:00+08:00",
  "exit_code": 2,
  "exit_reason": "UPDATES_APPLIED",
  "pkg_manager": "apt",
  "updates": {"total": 14, "security": 3, "critical": 1, "flatpak": 2, "snap": 0},
  "packages": [{"name": "openssl", "from": "3.0.10", "to": "3.0.11", "priority": "CRITICAL"}],
  "reboot_required": false,
  "snapshot_id": null,
  "deferred": false,
  "duration_seconds": 4
}
```

## Scheduling

| Mode | Behavior |
|------|----------|
| `login` (default) | Check every login |
| `daily` | Check once per `SCHEDULE_INTERVAL_HOURS` |
| `weekly` | Check once per `SCHEDULE_INTERVAL_HOURS × 7` |

Use XDG autostart (default) or systemd user timer:

```bash
./install.sh --systemd   # Install with systemd timer
./install.sh --xdg       # Install with XDG autostart
```

## Screenshots

<!-- TODO: Add terminal screenshots showing:
     1. dunstify notification with update prompt
     2. kdialog/zenity update dialog
     3. TUI setup wizard with bunny mascot
     4. Terminal output with security priority classification
     5. JSON output example
     Capture with: script -q /dev/null -c "nudge --check-only" | ansifilter
     Or use asciinema/svg-term for animated recordings -->

*Screenshots coming soon.*

## Development

### Run Tests

```bash
make test    # Requires bats-core
```

### Lint

```bash
make lint    # Requires shellcheck
```

### Man Page

```bash
man ./share/man/nudge.1    # Preview locally
```

## Troubleshooting

**nudge doesn't run at login:**
- Check autostart: `ls ~/.config/autostart/nudge.desktop` or `systemctl --user status nudge.timer`
- Verify `ENABLED=true` in `~/.config/nudge/nudge.conf`

**"No supported notification backend found":**
- Install a dialog tool: `sudo apt install kdialog` (KDE), `sudo apt install zenity` (GNOME/XFCE), or `sudo apt install dunst` (tiling WMs)

**Network check always fails:**
- Try a different `NETWORK_HOST` (e.g., `1.1.1.1`)
- Increase `NETWORK_TIMEOUT` and `NETWORK_RETRIES`
- Set `OFFLINE_MODE="notify"` to see when network is down

**Config errors:**
- Run `nudge --validate` to check config
- Run `nudge --config` to see resolved values
- Run `nudge --migrate` if upgrading from v1.x

**Package manager not detected:**
- Set `PKGMGR_OVERRIDE="apt"` (or dnf/pacman/zypper) in config

## Safety

nudge runs your configured update command when you accept. Please read [SAFETY.md](docs/SAFETY.md) — it covers the risks of system updates, PPA concerns, and shared-account considerations.

## Security

To report a security vulnerability, **do not open a public issue.** See [SECURITY.md](.github/SECURITY.md) for the responsible disclosure process.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for the Contributor License Agreement, code conventions, and PR process.

## Project Stats

| Metric | Value |
|--------|-------|
| Test suite | 332+ tests across 16 files |
| Library modules | 15 modular `.sh` files |
| Named exit codes | 13 scriptable exit codes |
| Config keys | 33 validated keys |
| Notification backends | 5 with auto-detection |
| Package managers | 4 + Flatpak + Snap |
| Bunny poses | 10 ASCII art poses |
| Bunny dialogue lines | 100+ rotating messages |
| CI pipeline | ShellCheck + BATS on every PR |

## Project

- [ROADMAP.md](docs/ROADMAP.md) — Feature roadmap and deliberately out-of-scope items
- [CHANGELOG.md](docs/CHANGELOG.md) — Release history
- [CREDITS-AND-COMMUNITY.md](docs/CREDITS-AND-COMMUNITY.md) — Attribution and IP framework
- [CODE_OF_CONDUCT.md](docs/CODE_OF_CONDUCT.md) — Community standards
- [STANDARDS.md](docs/STANDARDS.md) — Repository standards and conventions

## License

Proprietary source-available. Copyright (c) 2026 OFFTRACKMEDIA Studios (ABN: 84 290 819 896).
All rights reserved. Free for personal, non-commercial use. Commercial use requires written consent.
See [LICENSE](LICENSE) and [EULA/OFFTRACKMEDIA_EULA_2025.txt](EULA/OFFTRACKMEDIA_EULA_2025.txt).

---

OFFTRACKMEDIA Studios — *Building Empires, Not Just Brands.*
