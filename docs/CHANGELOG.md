# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.0] — 2026-10-09

The public release: BSD 3-Clause, the selection menu, the bugs that made every
login an error, and a hardening pass.

### Added
- **The selection menu.** After Update Now, a terminal window lists every source
  of updates (system packages, Flatpak, Snap) with its subcategories (critical,
  security and other packages; applications and runtimes; snaps), with select-all
  at each level and single-package picking. Only what is ticked is applied; a
  subset runs `apt-get install --only-upgrade`, `dnf upgrade` or `zypper update`
  with the chosen names, and Arch stays all-or-nothing. `SELECT_UPDATES` (bool,
  default true) turns the menu off.
- The upgrade session runs inside the terminal: the optional snapshot, the system
  upgrade, Flatpak and Snap all run where `sudo` can ask for a password, and the
  result is reported back through a status file, so APPLIED and FAILED are true.
- `nudge` is installed as a command (a link to `nudge.sh`), so the documented
  commands and the bash completion work.
- Per-package security flags from the suite (`-security`) and the architecture
  (`libxml2:i386`) in the preview and the JSON (`arch`, `security`), plus a
  `selected` block in the JSON output.
- A timer or login run with no display records `SKIPPED_NO_DISPLAY` and exits 0;
  a passive backend (gdbus, notify-send) records `NOTIFIED` instead of a decline.
- `--check-only` prints a count at zero updates; `--validate` reports what the
  config parser had to reject; config lines accept `KEY = value`, `export KEY=`
  and inline `# comments`.
- The Nudge Bunny as an SVG character: seven moods and two poses drawn by one
  generator, the app icon installed to the hicolor theme and shown by every
  dialog backend, a mood sheet and a social preview; the text bunny for
  terminals redrawn in the same proportions (eleven poses, faces in the head).
- Tests: 17 files; negative assertions are real (`run !`), and every review
  finding has a regression test.

### Fixed
- The apt parser read the suite name as the new version and never flagged
  security packages; the preview sorted STANDARD first.
- `--check-only --json` ended with terminal escape codes and did not parse.
- The reboot flag never cleared after a reboot, so nudge asked to reboot at
  every login; the kernel check also compared across flavours (`oem` vs
  `generic`) and on Arch compared two spellings of the same version.
- A lock fallback that made a fresh directory per run (no mutual exclusion) and
  an unlink that let a third instance in.
- Custom-prefix installs could not find their libraries.
- The configure screen crashed on an unbound array index; a word at a numbered
  prompt crashed the TUI; an out-of-range number in Configure started the install;
  the TUI exited silently when stdout was not a terminal; "Install & run" died
  under `pipefail`; edits made before a fresh install were discarded.
- An upgrade through setup dropped `TERMINAL_EMULATOR` and
  `CRITICAL_PACKAGES_EXTRA` and switched systemd installs back to XDG autostart.
- `--check-only` and `--dry-run` stamped `last_check`, wrote history, reset the
  streak and queued offline checks; an expired "remind me later" fell through to
  the daily interval; a 24h timer missed every second run by 50 seconds.
- An offline run under `set -e` printed no JSON; offline (5) and a second
  instance (7) are no longer crash reports.
- kdialog buttons are labelled Update Now / Remind Me Later / Not Now and map
  correctly; the preview honours `AUTO_DISMISS`; a dialog that cannot open the
  display is a backend failure, not a decline; the kdialog deferral list no
  longer shows every option twice; an unparseable deferral choice fails loudly.
- `HISTORY_MAX_LINES=0` wiped the history; `--history N --since` ignored N;
  `LOG_FILE` got nothing in JSON mode; the zypper parser read the repository as
  the package name; the dnf parser cut names at the first dot; the timeshift
  snapshot id parsed to its tag; the btrfs snapshot used an unusable source.
- `--defer`, `--since`, `--file` and `--clear` without their value or parent flag
  are usage errors instead of silent full runs.
- The installed `nudge-setup.sh` re-downloaded the repository on every run.
- The birthday decoration fired on the install day.

### Security
- `UPDATE_COMMAND` is parsed by a grammar (optional `sudo`, a known package tool,
  plain arguments, chained with ` && `) and executed as argument vectors; there
  is no `bash -c` in the upgrade path, and a customised command is shown in the
  dialog. The old denylist accepted `&&`, `||`, pipes after `sudo`, redirects,
  `-o APT::...::Pre-Invoke` and more.
- `TERMINAL_EMULATOR` is an allowlist of known terminals resolved to a
  system-installed, non-user-writable program.
- State files are data: `bunny_last_message`, the session status `pid` and
  every timestamp are validated before any arithmetic, `kill` or `date -d`.
- The config file must be a regular file owned by the user with no group or
  world write; it is written atomically with mode 0600; `LOG_FILE` must be a
  regular file; `NETWORK_HOST` starts and ends alphanumeric and reaches `ping`
  after `--`; integers reject leading zeros; deferrals cap at 30 days.
- Self-update: https-only with no downgrade on redirect, GitHub hosts only,
  validated release versions, extraction into a private directory without
  special files, and every shipped script must match `SHA256SUMS`.
- Crash reports scrub home paths, the user name, the update command, the package
  inventory and `NETWORK_HOST`; `--report --file` shows the full issue before
  asking.
- Package labels lose control characters before they reach the terminal; the
  session and status files are private (0600) and the session file must be.
- The release workflow pins actions by commit, grants `contents: write` to the
  release job only, hashes every shipped file, and marks `-` tags pre-release;
  the installer bootstrap fails loudly offline and takes no deletable path as a
  flag.

### Changed
- BSD 3-Clause license for the whole repository (code and documentation),
  declared per path in REUSE.toml; the proprietary notice and the EULA are gone.
- The config format version is 2.1.0 (`SELECT_UPDATES` added; existing files are
  migrated with a backup).
- The systemd service no longer hardcodes `DISPLAY=:0`; it runs only when the
  user manager has a display.
- `UPDATE_COMMAND` is honoured on every package manager once changed from the
  shipped default.

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
- `CONTRIBUTING.md`
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

[2.1.0]: https://github.com/otmof-ops/nudge/releases/tag/v2.1.0
