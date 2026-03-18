# Credits, Intellectual Property & Community

**nudge** — A gentle nudge to keep your system fresh.

Copyright (c) 2026 OFFTRACKMEDIA Studios (ABN: 84 290 819 896). All rights reserved.

---

## Credits and Acknowledgements

### Inspiration

nudge was inspired by the interactive update dialog in [Parrot OS](https://www.parrotsec.org/), which prompts users to update their system at login in a clean, user-friendly way. Rather than silent background updates or nagware-style popups, nudge follows the same philosophy: ask once, respect the answer.

### Tools and Dependencies

The following tools make nudge possible. They are the work of their respective authors and communities:

| Tool | Purpose in nudge | Authors |
|------|-----------------|---------|
| **kdialog** | Native KDE dialog prompts | KDE Project |
| **zenity** | GNOME/GTK dialog prompts | GNOME Project |
| **notify-send** | Desktop notification fallback | freedesktop.org |
| **konsole** | Terminal for running updates (KDE) | KDE Project |
| **apt** | Package management | Debian Project |
| **apt-check** | Security update detection | Ubuntu / Canonical |
| **XDG Autostart** | Login-time script execution | freedesktop.org |
| **shellcheck** | Shell script linting (CI) | Vidar Holen |

---

## Intellectual Property Framework

### OTM Position Statement

nudge is proprietary software owned by OFFTRACKMEDIA Studios. We use open-source tools as runtime dependencies — we do not bundle, modify, or redistribute them.

### Content Ownership

| Content | Owner |
|---------|-------|
| nudge source code, scripts, configuration | OFFTRACKMEDIA Studios |
| nudge documentation, README, governance files | OFFTRACKMEDIA Studios |
| kdialog, zenity, notify-send, konsole, apt | Their respective authors (see above) |
| XDG Autostart specification | freedesktop.org |

### IP Concerns

If you believe any content in this repository infringes your intellectual property rights:

1. **Identify** the specific content and your claim of ownership.
2. **Contact** OFFTRACKMEDIA Studios via GitHub Issues or the email in the EULA.
3. **Response** within 48 hours of acknowledgement.
4. **Resolution** within 72 hours for verified claims.

---

## Community Participation

### Feature Requests

Feature requests are welcome via [GitHub Issues](https://github.com/otmof-ops/nudge/issues) using the Feature Request template. Please include:

- A clear description of the feature
- Your use case (what problem it solves)
- Your desktop environment and distribution

### Bug Reports

Bug reports should use the [Bug Report template](https://github.com/otmof-ops/nudge/issues) and include system information (distro, DE, notification backend).

---

(c) 2026 OFFTRACKMEDIA Studios · ABN 84 290 819 896
