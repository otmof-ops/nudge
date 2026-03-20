# Credits, Intellectual Property & Community

**OFFTRACKMEDIA Studios — nudge**

This file covers three things: who gets credit for the work that made this project possible, how we handle intellectual property, and how the community can participate.

Copyright (c) 2026 OFFTRACKMEDIA Studios (ABN: 84 290 819 896). All rights reserved.

---

## Table of Contents

- [Part 1 — Credits and Acknowledgements](#part-1--credits-and-acknowledgements)
- [Part 2 — Intellectual Property Framework](#part-2--intellectual-property-framework)
- [Part 3 — Community](#part-3--community)

---

## Part 1 — Credits and Acknowledgements

### Inspiration

nudge was inspired by the interactive update dialog in [Parrot OS](https://www.parrotsec.org/), which prompts users to update their system at login in a clean, user-friendly way. Rather than silent background updates or nagware-style popups, nudge follows the same philosophy: ask once, respect the answer.

### Tools and Dependencies

The following tools make nudge possible. They are the work of their respective authors and communities:

| Tool | Purpose | Authors |
|------|---------|---------|
| **kdialog** | KDE dialog prompts | KDE Project |
| **zenity** | GNOME/GTK dialog prompts | GNOME Project |
| **dunstify** | Dunst notification actions | dunst maintainers |
| **gdbus** | D-Bus notification fallback | GNOME/GLib |
| **notify-send** | Desktop notification fallback | freedesktop.org |
| **konsole** | Terminal for updates (KDE) | KDE Project |
| **gnome-terminal** | Terminal for updates (GNOME) | GNOME Project |
| **xfce4-terminal** | Terminal for updates (XFCE) | XFCE Project |
| **apt** | Package management (Debian/Ubuntu) | Debian Project |
| **dnf** | Package management (Fedora/RHEL) | Fedora Project |
| **pacman** | Package management (Arch) | Arch Linux |
| **zypper** | Package management (openSUSE) | openSUSE Project |
| **flatpak** | Flatpak package management | Flatpak Project |
| **snap** | Snap package management | Canonical |
| **apt-check** | Security update detection | Ubuntu / Canonical |
| **timeshift** | System snapshot tool | Tony George / Linux Mint |
| **snapper** | Filesystem snapshot tool | openSUSE Project |
| **flock** | File locking (util-linux) | util-linux maintainers |
| **bats-core** | Bash testing framework (CI) | bats-core contributors |
| **shellcheck** | Shell script linting (CI) | Vidar Holen |
| **XDG Autostart** | Login-time script execution | freedesktop.org |
| **systemd** | Timer-based scheduling | systemd Project |

---

### Research and References

| Source | How It Informed This Project |
|--------|------------------------------|
| [Parrot OS](https://www.parrotsec.org/) | Inspiration for interactive login-time update prompt UX |
| [Keep a Changelog](https://keepachangelog.com/) | CHANGELOG format standard |
| [Semantic Versioning](https://semver.org/) | Versioning scheme |
| [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/latest/) | Config and data file locations |

---

## Part 2 — Intellectual Property Framework

### OTM Position Statement

nudge is proprietary software owned by OFFTRACKMEDIA Studios. We use open-source tools as runtime dependencies — we do not bundle, modify, or redistribute them.

### Content Ownership

| Content | Owner |
|---------|-------|
| nudge source code, scripts, configuration | OFFTRACKMEDIA Studios |
| nudge documentation, README, governance files | OFFTRACKMEDIA Studios |
| kdialog, zenity, dunstify, gdbus, notify-send, konsole, gnome-terminal, xfce4-terminal, apt, dnf, pacman, zypper, flatpak, snap, timeshift, snapper, flock, bats-core, shellcheck | Their respective authors (see above) |
| XDG Autostart specification | freedesktop.org |

### Attribution Requirements

If you use or reference this project, please provide attribution as follows:

```
nudge by OFFTRACKMEDIA Studios — https://github.com/otmof-ops/nudge
Licensed under the OFFTRACKMEDIA Source-Available License
```

### IP Removal Requests

If you believe any content in this repository infringes your intellectual property rights:

1. Open an issue at [GitHub Issues](https://github.com/otmof-ops/nudge/issues) with the subject "IP Removal Request"
2. Include: the specific content, proof of ownership, and the requested action
3. We will respond within 5 business days

### What Will Not Be Removed

- References to publicly available information
- Fair use commentary, analysis, and criticism
- Factual statements and publicly known technical specifications

---

## Part 3 — Community

### Feature Requests

Feature requests are welcome via [GitHub Issues](https://github.com/otmof-ops/nudge/issues) using the Feature Request template. Please include:

- A clear description of the feature
- Your use case (what problem it solves)
- Your desktop environment and distribution

### Bug Reports

Bug reports should use the [Bug Report template](https://github.com/otmof-ops/nudge/issues) and include system information (distro, DE, notification backend).

### Contribute Code

See [CONTRIBUTING.md](CONTRIBUTING.md) for the Contributor License Agreement, code conventions, and PR process.

### Code of Conduct

All community members are expected to behave professionally and respectfully. See our [Code of Conduct](CODE_OF_CONDUCT.md) for details.

---

(c) 2026 OFFTRACKMEDIA Studios · ABN 84 290 819 896
