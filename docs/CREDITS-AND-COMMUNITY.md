# Credits & Community

This file covers two things: who gets credit for the work that made this project possible, and how the community can participate.

---

## Table of Contents

- [Part 1 — Credits and Acknowledgements](#part-1--credits-and-acknowledgements)
- [Part 2 — Licensing](#part-2--licensing)
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

## Part 2 — Licensing

nudge is BSD 3-Clause ([LICENSE](../LICENSE)); Jay Taylor holds the copyright. The tools above are
runtime dependencies: nudge calls them and does not bundle, modify or redistribute any of them, so
each keeps its own license.

### Attribution

Nothing beyond the license's own condition is required: every copy keeps the copyright line. If you
want to credit the project, this is the preferred form:

```
nudge by Jay Taylor — https://github.com/otmof-ops/nudge (BSD 3-Clause)
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

See [CONTRIBUTING.md](CONTRIBUTING.md) for the code conventions, the sign-off, and the PR process.

### Code of Conduct

All community members are expected to behave professionally and respectfully. See our [Code of Conduct](CODE_OF_CONDUCT.md) for details.

