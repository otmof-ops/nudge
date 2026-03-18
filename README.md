# nudge

[![ShellCheck](https://github.com/otmof-ops/nudge/actions/workflows/validate-pr.yml/badge.svg)](https://github.com/otmof-ops/nudge/actions/workflows/validate-pr.yml)
[![Latest Release](https://img.shields.io/github/v/release/otmof-ops/nudge?label=release)](https://github.com/otmof-ops/nudge/releases)
[![License](https://img.shields.io/badge/license-Proprietary-red)](EULA/OFFTRACKMEDIA_EULA_2025.txt)

**A gentle nudge to keep your system fresh.**

Lightweight system update manager for Linux desktops. Checks for available packages after login and asks if you'd like to update — supports multiple distributions, package managers, notification backends, Flatpak, Snap, scheduling, deferral, snapshots, and more.

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

nudge v2.0.0 uses a modular library design — the main script is a ~150-line dispatcher that sources 10 modules from `lib/`:

| Module | Purpose |
|--------|---------|
| `lib/output.sh` | Exit codes, logging, JSON output |
| `lib/config.sh` | Safe config parser, validation, migration |
| `lib/lock.sh` | flock-based instance locking |
| `lib/network.sh` | Multi-method network probe (curl/wget/ping) |
| `lib/pkgmgr.sh` | apt/dnf/pacman/zypper + flatpak + snap |
| `lib/notify.sh` | dunstify/kdialog/zenity/gdbus/notify-send backends |
| `lib/schedule.sh` | Scheduling, interval guards, deferral |
| `lib/history.sh` | JSONL history log and viewer |
| `lib/safety.sh` | Pre-upgrade snapshots, reboot detection |
| `lib/selfupdate.sh` | GitHub release self-update check |

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

### Interactive Install

```bash
git clone git@github.com:otmof-ops/nudge.git
cd nudge
./install.sh
```

The installer walks you through all 32 settings, detects your environment, and offers a choice of XDG autostart or systemd timer.

### Quick Install (defaults)

```bash
./install.sh --defaults
```

### Scripted / Unattended Install

```bash
./install.sh --unattended
```

### Upgrade from v1.x

```bash
./install.sh --upgrade
```

Preserves your existing config, runs migration to add new keys with defaults.

### Installer Options

| Flag | Description |
|------|-------------|
| `--defaults` | Skip prompts, use default settings |
| `--unattended` | Non-interactive install (implies `--defaults`) |
| `--upgrade` | In-place upgrade, preserve config, run migration |
| `--config-only` | Re-run wizard without reinstalling scripts |
| `--systemd` | Use systemd user timer for autostart |
| `--xdg` | Use XDG autostart entry |
| `--no-completion` | Skip bash completion install |
| `--no-man` | Skip man page install |
| `--no-color` | Disable colored output |
| `--prefix=PATH` | Custom install prefix (default: `$HOME`) |

### Installed Files

| File | Purpose |
|------|---------|
| `~/.local/bin/nudge.sh` | Main dispatcher script |
| `~/.local/lib/nudge/*.sh` | Library modules (10) |
| `~/.config/nudge/nudge.conf` | Configuration (32 keys) |
| `~/.config/autostart/nudge.desktop` | XDG autostart entry |
| `~/.config/systemd/user/nudge.timer` | systemd timer (if selected) |
| `~/.config/systemd/user/nudge.service` | systemd service (if selected) |
| `~/.local/share/bash-completion/completions/nudge` | Bash completion |
| `~/.local/share/man/man1/nudge.1` | Man page |
| `~/.local/share/nudge/` | History, state, deferral files |

## Uninstall

```bash
./uninstall.sh
```

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
| `EXIT_ON_HELD` | bool | `true` | Skip held/pinned packages |

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
man ./nudge.1    # Preview locally
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

nudge runs your configured update command when you accept. Please read [SAFETY.md](SAFETY.md) — it covers the risks of system updates, PPA concerns, and shared-account considerations.

## Security

To report a security vulnerability, **do not open a public issue.** See [SECURITY.md](SECURITY.md) for the responsible disclosure process.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the Contributor License Agreement, code conventions, and PR process.

## Project

- [ROADMAP.md](ROADMAP.md) — Feature roadmap and deliberately out-of-scope items
- [CHANGELOG.md](CHANGELOG.md) — Release history
- [CREDITS-AND-COMMUNITY.md](CREDITS-AND-COMMUNITY.md) — Attribution and IP framework
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) — Community standards

## License

Proprietary. Copyright (c) 2026 OFFTRACKMEDIA Studios (ABN: 84 290 819 896).
All rights reserved. See [EULA/OFFTRACKMEDIA_EULA_2025.txt](EULA/OFFTRACKMEDIA_EULA_2025.txt).

---

OFFTRACKMEDIA Studios — *Building Empires, Not Just Brands.*
