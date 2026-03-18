# nudge

[![ShellCheck](https://github.com/otmof-ops/nudge/actions/workflows/validate-pr.yml/badge.svg)](https://github.com/otmof-ops/nudge/actions/workflows/validate-pr.yml)
[![Latest Release](https://img.shields.io/github/v/release/otmof-ops/nudge?label=release)](https://github.com/otmof-ops/nudge/releases)
[![License](https://img.shields.io/badge/license-Proprietary-red)](EULA/OFFTRACKMEDIA_EULA_2025.txt)

**A gentle nudge to keep your system fresh.**

Lightweight login-time update prompt for Linux desktops. Inspired by Parrot OS's interactive update dialog — nudge checks for available packages after login and asks if you'd like to update, right from your desktop.

## How It Works

```
Login → XDG autostart → nudge.sh → delay (configurable) → network check →
apt lock check → count available updates → if 0: exit silent →
if >0: prompt via kdialog/zenity/notify-send → "Update Now": terminal with
apt full-upgrade → "Not Now": exit
```

- Waits for your desktop to settle before checking (configurable delay)
- Skips silently if the system is already up to date
- Auto-detects your desktop environment and picks the best notification backend
- Opens a terminal with your configured update command if you accept
- PID lock prevents duplicate instances
- Detects security updates separately via `apt-check`
- Optional logging of all update checks and results

## Features

- Multi-desktop support: KDE Plasma, GNOME, XFCE, and generic fallbacks
- Interactive installer with settings wizard
- Configurable via `~/.config/nudge.conf` (11 options)
- `--dry-run` and `--check-only` modes for testing
- Clean uninstaller with `--yes` and `--keep-config` flags
- User-space installation — no root required to install

## Supported Desktop Environments

| Desktop | Dialog Backend | Terminal | Status |
|---------|---------------|----------|--------|
| KDE Plasma | `kdialog` | `konsole` | Full support |
| GNOME | `zenity` | `gnome-terminal` | Full support |
| XFCE | `zenity` | `xfce4-terminal` | Full support |
| Other | `notify-send` | `x-terminal-emulator` | Notification only (no interactive prompt) |

## Notification Backends

| Backend | Interactive Prompt | Auto-Dismiss | Desktop |
|---------|-------------------|--------------|---------|
| `kdialog` | Yes (Yes/No dialog) | Yes | KDE Plasma |
| `zenity` | Yes (Question dialog) | Yes (native timeout) | GNOME, XFCE |
| `notify-send` | No (notification only) | N/A | Any with libnotify |

## Requirements

- Ubuntu or Debian-based distribution
- One of: `kdialog`, `zenity`, or `libnotify-bin` (`notify-send`)
- A terminal emulator (`konsole`, `gnome-terminal`, `xfce4-terminal`, or `x-terminal-emulator`)

## Install

### Interactive Install

```bash
git clone git@github.com:otmof-ops/nudge.git
cd nudge
./install.sh
```

The installer walks you through each setting with sensible defaults. It auto-detects your desktop environment and picks the best notification backend.

### Quick Install (defaults)

```bash
./install.sh --defaults
```

### Scripted / Unattended Install

```bash
./install.sh --unattended
```

### Installer Options

| Flag | Description |
|------|-------------|
| `--defaults` | Skip prompts, use default settings |
| `--unattended` | Non-interactive install (implies `--defaults`) |
| `--no-color` | Disable colored output |
| `--prefix=PATH` | Custom install prefix (default: `$HOME`) |
| `--version` | Print version and exit |

### Installed Files

- `~/.local/bin/nudge.sh` — main script
- `~/.config/autostart/nudge.desktop` — autostart entry
- `~/.config/nudge.conf` — configuration

## Uninstall

```bash
./uninstall.sh
```

Shows what will be removed and asks for confirmation.

| Flag | Description |
|------|-------------|
| `--yes`, `-y` | Skip confirmation prompts |
| `--keep-config` | Preserve `~/.config/nudge.conf` |
| `--no-color` | Disable colored output |

## Configuration

Edit `~/.config/nudge.conf`:

| Option | Default | Description |
|--------|---------|-------------|
| `ENABLED` | `true` | Set to `false` to disable nudge without removing it |
| `DELAY` | `45` | Seconds to wait after login before checking |
| `CHECK_SECURITY` | `true` | Highlight security updates separately in the prompt |
| `AUTO_DISMISS` | `0` | Auto-dismiss dialog after N seconds (0 = never) |
| `UPDATE_COMMAND` | `sudo apt update && sudo apt full-upgrade` | Command to run for system update |
| `NETWORK_HOST` | `archive.ubuntu.com` | Host to ping for connectivity check |
| `NETWORK_TIMEOUT` | `5` | Ping timeout in seconds |
| `NETWORK_RETRIES` | `2` | Retry count before giving up on network |
| `NOTIFICATION_BACKEND` | `auto` | `kdialog`, `zenity`, `notify-send`, or `auto` |
| `LOG_FILE` | *(empty)* | Path to log file (empty = no logging) |

## CLI Flags

```bash
nudge.sh --version      # Print version
nudge.sh --dry-run      # Run checks, print what would happen, don't show dialogs
nudge.sh --check-only   # Print update count and exit
nudge.sh --help         # Show help
```

## Troubleshooting

**nudge doesn't run at login:**
- Check that `~/.config/autostart/nudge.desktop` exists
- Verify your DE supports XDG autostart (`ls ~/.config/autostart/`)
- Check `ENABLED=true` in `~/.config/nudge.conf`

**"No supported notification backend found":**
- Install a dialog tool: `sudo apt install kdialog` (KDE) or `sudo apt install zenity` (GNOME/XFCE)

**Updates detected but dialog doesn't appear:**
- Run `nudge.sh --dry-run` to see what backend is being used
- Check that `NOTIFICATION_BACKEND` in config matches an installed tool

**Network check always fails:**
- Try a different `NETWORK_HOST` (e.g., `8.8.8.8` or `1.1.1.1`)
- Increase `NETWORK_TIMEOUT` and `NETWORK_RETRIES`

**APT lock conflict:**
- nudge exits silently if another package manager is running
- Wait for the other operation to finish, then test with `nudge.sh --check-only`

**Logging:**
- Set `LOG_FILE="/home/youruser/.local/share/nudge/nudge.log"` in config
- Then check the log: `cat ~/.local/share/nudge/nudge.log`

## Safety

nudge runs `sudo apt full-upgrade` when you accept an update. Please read [SAFETY.md](SAFETY.md) before use — it covers the risks of automated system updates, PPA concerns, and shared-account considerations.

## Security

To report a security vulnerability, **do not open a public issue.** See [SECURITY.md](SECURITY.md) for the responsible disclosure process.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the Contributor License Agreement, code conventions, and PR process.

## Project

- [ROADMAP.md](ROADMAP.md) — Feature roadmap (v1.0 → v2.0)
- [CHANGELOG.md](CHANGELOG.md) — Release history
- [CREDITS-AND-COMMUNITY.md](CREDITS-AND-COMMUNITY.md) — Attribution and IP framework
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) — Community standards

## License

Proprietary. Copyright (c) 2026 OFFTRACKMEDIA Studios (ABN: 84 290 819 896).
All rights reserved. See [EULA/OFFTRACKMEDIA_EULA_2025.txt](EULA/OFFTRACKMEDIA_EULA_2025.txt).

---

OFFTRACKMEDIA Studios — *Building Empires, Not Just Brands.*
