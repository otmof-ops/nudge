# Security Policy

**OFFTRACKMEDIA Studios** — ABN 84 290 819 896

## Supported Versions

| Version | Supported |
|---------|-----------|
| 2.0.x   | Yes       |
| 1.1.x   | No        |
| 1.0.x   | No        |

Only the latest release receives security updates.

## Reporting a Vulnerability

If you discover a security vulnerability in nudge, **do not open a public issue.** Instead:

1. **Email:** Send a detailed report to `otmof.mail@gmail.com` with the subject line `[SECURITY] nudge — <brief description>`.
2. **Include:**
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)
3. **Response:** You will receive an acknowledgement within **48 hours**.
4. **Resolution:** Verified vulnerabilities will be patched within **7 business days** for critical issues, **30 days** for non-critical issues.
5. **Disclosure:** We will coordinate disclosure with you. We request a **90-day embargo** from the date of report before public disclosure.

## Scope

The following are in scope for security reports:

- **Command injection** via configuration values (`UPDATE_COMMAND`, `NETWORK_HOST`, `LOG_FILE`)
- **Privilege escalation** beyond intended `sudo` usage
- **Path traversal** in file operations
- **Lock file race conditions** that could lead to unintended behavior
- **Unsafe temporary file handling**
- **JSON history file injection/tampering** (`~/.local/share/nudge/history.jsonl`)
- **Self-update MITM** (GitHub API check, tarball download, SHA256 verification)
- **Config parser injection** (nudge uses a safe line-by-line parser, not `source` — this design is a mitigation, but parser edge cases are in scope)
- **Deferral file timestamp manipulation** (bypassing scheduling constraints via crafted timestamps)
- **flock bypass attempts** (circumventing instance locking to force concurrent execution)

The following are **out of scope:**

- Vulnerabilities in upstream dependencies (`apt`, `dnf`, `pacman`, `zypper`, `flatpak`, `snap`, `kdialog`, `zenity`, `konsole`, `dunstify`, `gdbus`)
- Issues requiring physical access to the machine
- Social engineering attacks
- Denial of service against the local system (nudge runs once per login/timer and exits)

## Security Design

nudge follows these security principles:

- **Minimal privilege:** Installs entirely in user-space (`~/.local/bin/`, `~/.config/`). Only the update command itself requires `sudo`, and the user is prompted by the system for their password.
- **Network:** nudge uses `curl`, `wget`, and/or `ping` for connectivity checking. It opens no ports and accepts no inbound connections.
- **Self-update:** When self-update is enabled, nudge makes outbound HTTPS requests to the GitHub API to check for new releases (rate-limited, checked at most once per 24 hours). Downloads are verified against a SHA256 checksum before installation.
- **No data exfiltration:** nudge does not transmit any system information, update counts, or usage telemetry to any remote server.
- **No persistent daemons:** nudge runs once at login (XDG autostart) or on a systemd user timer schedule, performs its check, and exits. No persistent background processes remain.
- **Config:** Config is read from `~/.config/nudge/nudge.conf` using a safe line-by-line parser. nudge never `source`s the config file, making it resistant to code injection via configuration values.
- **Locking:** Instance locking uses `flock`, which is kernel-managed. There are no stale lock files — the lock is released automatically when the process exits.
- **History:** Update history is written to a local JSONL file (`~/.local/share/nudge/history.jsonl`). No history data is transmitted remotely.

## Acknowledgements

We will credit security researchers who report valid vulnerabilities (with their permission) in our [CREDITS-AND-COMMUNITY.md](../docs/CREDITS-AND-COMMUNITY.md) file.

---

(c) 2026 OFFTRACKMEDIA Studios · ABN 84 290 819 896
