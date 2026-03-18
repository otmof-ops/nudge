# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] — 2026-03-19

### Added
- Interactive installer with settings wizard (`install.sh`)
- `--defaults` and `--unattended` installer flags for scripted installs
- `--no-color` flag across installer and uninstaller
- `--prefix=PATH` installer flag for custom install locations
- Desktop environment auto-detection (KDE, GNOME, XFCE, generic)
- Multi-backend notification support: `kdialog`, `zenity`, `notify-send`
- `--dry-run` flag — run checks without showing dialogs
- `--check-only` flag — print update count and exit
- `--version` flag on all scripts
- 9 new configuration options: `CHECK_SECURITY`, `AUTO_DISMISS`, `UPDATE_COMMAND`, `NETWORK_HOST`, `NETWORK_TIMEOUT`, `NETWORK_RETRIES`, `NOTIFICATION_BACKEND`, `LOG_FILE`
- Optional logging of update checks and results
- Terminal emulator auto-detection (konsole, gnome-terminal, xfce4-terminal)
- Config backup on reinstall
- Uninstaller `--yes` and `--keep-config` flags
- Colored output with `--no-color` support
- GitHub Actions CI: shellcheck + bash syntax validation on every PR
- GitHub Actions release workflow: tag-triggered GitHub Releases
- Issue templates: bug report (with system info fields) and feature request
- Pull request template with shellcheck/testing checklist
- `CONTRIBUTING.md` with Contributor License Agreement
- `CREDITS-AND-COMMUNITY.md` with attribution and IP framework
- `SAFETY.md` with system modification risk documentation
- `ROADMAP.md` with feature roadmap v1.0→v2.0
- `SECURITY.md` with vulnerability disclosure policy
- `CODE_OF_CONDUCT.md`
- `CHANGELOG.md`
- `.editorconfig` for consistent formatting
- `.gitignore` for common exclusions
- `.gitattributes` for line ending normalization

### Changed
- `nudge.sh` rewritten with multi-backend support, configurable network checks, logging, and CLI flags
- `install.sh` rewritten as interactive settings wizard with dependency auto-detection
- `uninstall.sh` enhanced with flags, colored output, preview of files to remove, and log cleanup
- `nudge.conf` expanded from 2 to 11 fully documented options
- `nudge.desktop` — removed `OnlyShowIn=KDE;` to support all desktop environments
- `README.md` rewritten with full option reference, DE support tables, troubleshooting, and badges

### Fixed
- Network check now uses configurable host, timeout, and retry count instead of hardcoded values
- Uninstaller now shows what will be removed before proceeding

## [1.0.0] — 2026-03-19

### Added
- Initial release
- Login-time update detection via XDG autostart
- Network connectivity check with retry
- APT lock detection
- Security update highlighting via `apt-check`
- Native `kdialog` prompt with `konsole` terminal
- PID-based lock to prevent duplicate instances
- Configurable delay and enable/disable toggle
- User-space installation
- `install.sh` and `uninstall.sh` scripts

[1.1.0]: https://github.com/otmof-ops/nudge/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/otmof-ops/nudge/releases/tag/v1.0.0
