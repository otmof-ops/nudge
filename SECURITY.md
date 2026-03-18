# Security Policy

**OFFTRACKMEDIA Studios** — ABN 84 290 819 896

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.1.x   | Yes       |
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

The following are **out of scope:**

- Vulnerabilities in upstream dependencies (`apt`, `kdialog`, `zenity`, `konsole`)
- Issues requiring physical access to the machine
- Social engineering attacks
- Denial of service against the local system (nudge runs once per login and exits)

## Security Design

nudge follows these security principles:

- **Minimal privilege:** Installs entirely in user-space (`~/.local/bin/`, `~/.config/`). Only the update command itself requires `sudo`, and the user is prompted by the system for their password.
- **No network listeners:** nudge makes one outbound `ping` for connectivity checking. It opens no ports and accepts no inbound connections.
- **No data exfiltration:** nudge does not transmit any system information, update counts, or usage telemetry to any remote server.
- **No persistent daemons:** nudge runs once at login, performs its check, and exits. No background processes remain.
- **Configuration sourced locally:** Config is read from `~/.config/nudge.conf` only. No remote configuration fetching.

## Acknowledgements

We will credit security researchers who report valid vulnerabilities (with their permission) in our [CREDITS-AND-COMMUNITY.md](CREDITS-AND-COMMUNITY.md) file.

---

(c) 2026 OFFTRACKMEDIA Studios · ABN 84 290 819 896
