# nudge — Roadmap

**OFFTRACKMEDIA Studios** — ABN 84 290 819 896

---

## Current Release

### v1.0.0 — Basic KDE Update Prompt (Released)

- Login-time update detection via XDG autostart
- Network connectivity check with retry
- APT lock detection (prevents conflicts with other package operations)
- Security update highlighting via `apt-check`
- Native `kdialog` prompt with `konsole` terminal for updates
- PID-based lock to prevent duplicate instances
- Configurable delay and enable/disable toggle
- User-space installation (no root required to install)

---

## Planned Releases

### v1.1.0 — Enhanced Installer & Multi-Desktop Support

- Interactive installer with settings wizard
- `--defaults` and `--unattended` flags for scripted installs
- Desktop environment auto-detection (KDE, GNOME, XFCE, generic)
- Multi-backend notification support: `kdialog`, `zenity`, `notify-send`
- Expanded configuration: security highlighting, auto-dismiss, custom update commands, network tuning, logging
- Colored output with `--no-color` support
- `--dry-run` and `--check-only` flags for testing
- Enhanced uninstaller with `--yes` and `--keep-config` flags
- GitHub Actions CI (shellcheck + syntax validation)
- Issue and PR templates
- Governance files (CONTRIBUTING, SAFETY, CREDITS, ROADMAP)

### v1.2.0 — Scheduling & History

- Configurable check frequency: every login, daily, weekly
- Update history log with timestamps and package counts
- `nudge --history` to view past update checks
- Optional desktop notification summary (non-blocking)
- Config migration tool for upgrading between versions

### v2.0.0 — Multi-Distribution Support

- Fedora/RHEL support (`dnf`)
- Arch Linux support (`pacman`)
- openSUSE support (`zypper`)
- Flatpak update integration
- Snap update integration
- Distribution auto-detection
- Package manager abstraction layer

---

## Contributing to the Roadmap

Feature requests are welcome via [GitHub Issues](https://github.com/otmof-ops/nudge/issues) using the Feature Request template. Community input directly influences prioritization of planned features.

---

(c) 2026 OFFTRACKMEDIA Studios · ABN 84 290 819 896
