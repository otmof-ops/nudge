# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- RFC 8259 compliant `json_escape` — handles all U+0001–U+001F control characters
- `_NUDGE_TRIGGER` input validation (whitelist: manual, login, timer, cron)
- NETWORK_HOST character validation in `config_load`
- UPDATE_COMMAND shell metacharacter warning in `config_load`
- PKGMGR_OVERRIDE validated as enum (empty, apt, dnf, pacman, zypper)
- Mandatory SHA256 checksum verification for self-update downloads
- `chmod 0644` for installed lib files in `install.sh`
- `--since` date validation in history viewer
- New tests: json_escape, notify_reboot, AUTO_DISMISS timeout, pkgmgr_lock_check, _build_upgrade_cmd, selfupdate_check, offline mode, reboot detection, --since filter, weekly schedule mode
- `test_notify.bats` added to test inventory

### Fixed
- `_finalize()` now used consistently for all exit paths (6 remaining inline blocks replaced)
- `local rc` scope in `_prompt_kdialog` — declaration moved before if/else block
- `snapshot_id` now properly JSON-escaped via `json_escape`
- `install.sh` compound condition simplified (redundant `USE_DEFAULTS` check removed)
- `install.sh` upgrade config parser uses `printf -v` instead of `declare` (matches safe pattern)
- `selfupdate_check_due` double-call removed — `selfupdate_check` already gates internally
- `nudge_version` in history records pre-escaped (eliminates per-record subshell)
- `history_rotate` uses `mktemp` instead of predictable `.tmp` path
- Lock file `/tmp` fallback uses `mktemp -d` instead of bare `/tmp`
- Network probe switched from HTTP to HTTPS
- Dynamic module count in `install.sh` (replaces hardcoded "10")

### Changed
- PKGMGR_OVERRIDE type changed from string to enum validation

### Removed
- `EXIT_ON_HELD` config key and `pkgmgr_check_held()` function (dead code)

## [2.0.0] — 2026-03-19

### Added
- **Modular architecture:** 10 library modules in `lib/` — output, config, lock, network, pkgmgr, notify, schedule, history, safety, selfupdate
- **Multi-distro support:** apt, dnf (Fedora/RHEL), pacman (Arch), zypper (openSUSE)
- **Flatpak integration:** auto-detection, update counting, and upgrade
- **Snap integration:** auto-detection, update counting, and upgrade
- **21 named exit codes** (0–13) for scripting and automation
- **JSON output mode** (`--json`) — single JSON object at exit with full session data
- **Structured logging:** 4 log levels (debug/info/warn/error) with `LOG_LEVEL` config
- **Safe config parser:** line-by-line parsing with type validation (bool/int/enum/string), never `source`
- **Config migration:** automatic upgrade from v1.1.0 config format, backup before migration
- **Config directory:** moved from `~/.config/nudge.conf` to `~/.config/nudge/nudge.conf`
- **flock-based locking** — replaces PID file, zero stale locks
- **Signal handling:** SIGINT/SIGTERM/SIGHUP trapped, orphaned dialogs cleaned up
- **Multi-method network probe:** curl → wget → ping fallback chain
- **Offline mode:** configurable behavior (skip/notify/queue) when network unavailable
- **dunstify notification backend** with action buttons
- **gdbus notification backend** (native D-Bus)
- **"Remind me later" button** on all interactive backends
- **Update preview:** scrollable package list shown before yes/no prompt
- **Priority classification:** CRITICAL/SECURITY/RECOMMENDED/STANDARD tiers
- **Scheduling:** login/daily/weekly check frequency with `SCHEDULE_MODE`
- **Update deferral:** configurable durations (1h/4h/1d), persistent state file
- **JSONL history log:** `~/.local/share/nudge/history.jsonl` with full session records
- **History viewer:** `--history [N]`, `--history --json`, `--history --since DATE`
- **Reboot detection:** post-upgrade check via distro-specific methods (reboot-required, needrestart, dnf needs-restarting, kernel version comparison)
- **Pre-upgrade snapshots:** optional timeshift/snapper/btrfs snapshot before upgrade
- **Self-update check:** GitHub API check with 24h rate limit, SHA256 verification
- **`--self-update` flag** for downloading and installing latest release
- **systemd user timer** as alternative to XDG autostart
- **Bash tab completion** for all flags with context-sensitive completions
- **Man page** (`nudge.1`) with full documentation of all options, config keys, exit codes
- **Makefile** with test, lint, install, uninstall targets
- **BATS test suite:** 10 test files, 80+ test cases covering all modules
- **20 new config keys** (30 total): CONF_VERSION, SCHEDULE_MODE, SCHEDULE_INTERVAL_HOURS, HISTORY_ENABLED, HISTORY_MAX_LINES, FLATPAK_ENABLED, SNAP_ENABLED, PREVIEW_UPDATES, SECURITY_PRIORITY, REBOOT_CHECK, SNAPSHOT_ENABLED, SNAPSHOT_TOOL, SELF_UPDATE_CHECK, SELF_UPDATE_CHANNEL, OFFLINE_MODE, DEFERRAL_OPTIONS, PKGMGR_OVERRIDE, DUNST_APPNAME, JSON_OUTPUT, LOG_LEVEL
- **New CLI flags:** `--json`, `--verbose`, `--history`, `--defer`, `--self-update`, `--config`, `--validate`, `--migrate`
- **Installer flags:** `--upgrade`, `--config-only`, `--systemd`, `--xdg`, `--no-completion`, `--no-man`
- **Installer upgrade detection:** prompts to upgrade/reinstall/cancel when nudge already installed
- **Post-install verification:** runs `nudge --version` to confirm functional install

### Changed
- `nudge.sh` rewritten as ~460-line thin dispatcher sourcing 10 modules from `lib/`
- `install.sh` rewritten with full wizard for all 30 config keys, systemd/XDG choice, upgrade support
- `uninstall.sh` upgraded to clean up systemd units, bash completion, man page, history, state files
- `nudge.conf` expanded from 11 to 30 fully documented configuration keys
- Library modules installed to `~/.local/lib/nudge/`
- CI updated to run shellcheck on all lib modules and BATS test suite
- kdialog auto-dismiss now uses `timeout` instead of background PID + sleep + kill
- Notification detection order updated: dunstify → kdialog → zenity → gdbus → notify-send

### Fixed
- Stale lock files eliminated by switching from PID file to flock
- Signal handling prevents orphaned dialog processes on Ctrl+C
- Config typos no longer crash the script (safe parser with fallback to defaults)
- Network check works on ICMP-restricted networks (curl/wget fallback)

### Removed
- Raw `source` config loading (replaced with safe parser)
- PID-based lock mechanism (replaced with flock)

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

[2.0.0]: https://github.com/otmof-ops/nudge/compare/v1.1.0...v2.0.0
[1.1.0]: https://github.com/otmof-ops/nudge/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/otmof-ops/nudge/releases/tag/v1.0.0

---

(c) 2026 OFFTRACKMEDIA Studios · ABN 84 290 819 896
