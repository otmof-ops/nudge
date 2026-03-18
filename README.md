# nudge

**A gentle nudge to keep your system fresh.**

Lightweight login-time update prompt for Ubuntu KDE Plasma desktops. Inspired by Parrot OS's interactive update dialog — nudge checks for available packages after login and asks if you'd like to update, right from your desktop.

## How It Works

```
Login → XDG autostart → nudge.sh → delay (45s) → network check →
apt lock check → count available updates → if 0: exit silent →
if >0: kdialog prompt → "Update Now": konsole with apt full-upgrade →
"Not Now": exit
```

- Waits for your desktop to settle before checking
- Skips silently if the system is already up to date
- Uses `kdialog` for a native KDE prompt
- Opens `konsole` with `sudo apt update && sudo apt full-upgrade` if you accept
- PID lock prevents duplicate instances
- Detects security updates separately via `apt-check`

## Requirements

- Ubuntu or Debian-based distribution
- KDE Plasma desktop
- `kdialog`
- `konsole`

## Install

```bash
git clone git@github.com:otmof-ops/nudge.git
cd nudge
./install.sh
```

The installer copies files to:
- `~/.local/bin/nudge.sh` — main script
- `~/.config/autostart/nudge.desktop` — KDE autostart entry
- `~/.config/nudge.conf` — configuration (only if not already present)

## Uninstall

```bash
./uninstall.sh
```

Removes all installed files. Asks before deleting your config.

## Configuration

Edit `~/.config/nudge.conf`:

| Option    | Default | Description                                      |
|-----------|---------|--------------------------------------------------|
| `ENABLED` | `true`  | Set to `false` to disable nudge without removing it |
| `DELAY`   | `45`    | Seconds to wait after login before checking       |

## License

Proprietary. Copyright (c) 2026 OFFTRACKMEDIA Studios (ABN: 84 290 819 896).
All rights reserved. See [EULA/OFFTRACKMEDIA_EULA_2025.txt](EULA/OFFTRACKMEDIA_EULA_2025.txt).

---

OFFTRACKMEDIA Studios — *Building Empires, Not Just Brands.*
