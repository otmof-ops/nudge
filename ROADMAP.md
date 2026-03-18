# nudge — Roadmap

**OFFTRACKMEDIA Studios** — ABN 84 290 819 896

---

## Released

### v1.0.0 — Basic KDE Update Prompt (Released)

- Login-time update detection via XDG autostart
- Network connectivity check with retry
- APT lock detection (prevents conflicts with other package operations)
- Security update highlighting via `apt-check`
- Native `kdialog` prompt with `konsole` terminal for updates
- PID-based lock to prevent duplicate instances
- Configurable delay and enable/disable toggle
- User-space installation (no root required to install)

### v1.1.0 — Enhanced Installer & Multi-Desktop Support (Released)

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

### v2.0.0 — Enterprise-Grade System Update Manager (Released)

- **Modular architecture:** 10 library modules, thin dispatcher main script
- **Multi-distribution:** apt, dnf, pacman, zypper package manager support
- **Flatpak + Snap integration**
- **21 named exit codes** for scripting and automation
- **JSON output mode** for machine consumption
- **Safe config parser** with type validation and migration
- **flock-based locking** — zero stale locks
- **Signal handling** — clean orphan cleanup
- **Multi-method network probe** — curl/wget/ping fallback
- **5 notification backends** — dunstify, kdialog, zenity, gdbus, notify-send
- **"Remind me later"** deferral with configurable durations
- **Update preview** with priority classification (CRITICAL/SECURITY/STANDARD)
- **Scheduling** — login/daily/weekly modes
- **JSONL history log** with CLI viewer and date filtering
- **Reboot detection** — distro-specific post-upgrade checks
- **Pre-upgrade snapshots** — timeshift/snapper/btrfs
- **Self-update** — GitHub release check with SHA256 verification
- **systemd user timer** as alternative to XDG autostart
- **Bash tab completion** for all flags
- **Man page** with full documentation
- **BATS test suite** — 80+ tests across 10 files
- **Makefile** for test/lint/install/uninstall
- **32 configuration keys** (up from 11)

---

## Deliberately Out of Scope

The following have been intentionally excluded from nudge's roadmap. These are documented to signal completeness, not oversight.

- **No GUI config editor** — config is a text file, that's the Unix way
- **No daemon mode** — nudge is a nudge, not a service
- **No remote management or fleet deployment** — nudge is a personal tool
- **No automatic rollback** — delegates to timeshift/snapper, the right tools for the job
- **No unattended auto-update** — nudge asks, never acts without user consent
- **No Wayland-specific backends** — existing backends (kdialog, zenity, dunstify) work under XWayland and native Wayland

---

## Contributing to the Roadmap

Feature requests are welcome via [GitHub Issues](https://github.com/otmof-ops/nudge/issues) using the Feature Request template. Community input directly influences prioritization of planned features.

---

(c) 2026 OFFTRACKMEDIA Studios · ABN 84 290 819 896
