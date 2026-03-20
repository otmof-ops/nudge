# nudge — Safety Framework

**OFFTRACKMEDIA Studios** — ABN 84 290 819 896
**Applies to:** All modules, components, and documentation in this repository

> **You are required to read and understand the safety documentation relevant to your work before using the content in this repository.** This is not optional.

---

## Why This Document Exists

nudge is a system update manager that runs package management commands with elevated privileges (`sudo`). This safety framework identifies the specific risks, legal obligations, and ethical responsibilities relevant to automated system modification.

---

## Safety Categories

Every component in this project falls into one or more of the following safety categories:

### Category A — Physical Safety

**Applicable to:** Not applicable — nudge is pure software with no hardware interaction.

**Risks:** None identified. nudge does not control, monitor, or interact with any physical hardware, industrial control systems, or safety-critical equipment.

### Category B — Cybersecurity & System Integrity

**Applicable to:** UPDATE_COMMAND execution, self-update mechanism, sudo operations, package manager interaction.

**Risks:** System compromise via malicious config injection, supply chain attacks via self-update, privilege escalation via crafted UPDATE_COMMAND.

**Key obligations:**
- Config parser uses `printf -v` — never `eval`, `source`, or `declare` with unvalidated input
- Self-update verifies SHA256 checksums
- All GitHub API requests use HTTPS
- nudge never stores or handles user credentials

### Category C — Data Privacy & Ethics

**Applicable to:** Network connectivity checks, self-update API calls, history logging.

**Risks:** Login time pattern leakage via network probes, local history files containing update records.

**Key obligations:**
- No telemetry — nudge transmits no usage data to any server
- Network probes use standard HTTP HEAD requests with no tracking headers
- History is stored locally in user-owned files only
- User can disable all network activity via OFFLINE_MODE

### Category D — Financial & Regulatory

**Applicable to:** License compliance, EULA terms, commercial use restrictions.

**Risks:** Unauthorized commercial use, license non-compliance.

**Key obligations:**
- Users must comply with the OFFTRACKMEDIA Source-Available License
- Commercial use requires prior written consent
- Contributors must agree to the CLA before submitting code

### Category E — Low Risk (Reference Material)

**Applicable to:** Documentation, governance files, test suite, man page, bash completion.

General reference material with no specific safety obligations beyond standard professional practice.

---

## System Modification Risks

nudge is a system update prompt. When you accept an update, it runs package management commands with elevated privileges (`sudo`). This modifies your system at the package level.

---

## Risks

### 1. Package Upgrades Can Break Your System

nudge supports multiple package managers (`apt`, `dnf`, `pacman`, `zypper`). Full system upgrades can remove packages, install new ones, and upgrade the kernel. In rare cases this can:

- Break hardware drivers (especially GPU drivers and Wi-Fi)
- Remove packages you depend on (dependency resolution conflicts)
- Require a reboot that you're not ready for (kernel upgrades)
- Fail mid-upgrade and leave your system in a partially upgraded state

**Mitigation:** Review what's being upgraded before confirming. Use your package manager's preview commands (`apt list --upgradable`, `dnf check-update`, `pacman -Qu`, `zypper list-updates`) to inspect pending upgrades. Maintain regular backups.

### 2. Third-Party Repository Risk

If you have added PPAs, COPR repos, AUR packages, or other third-party repositories, the upgrade will include their packages. These packages:

- Are not vetted by the distribution's security team
- May conflict with official packages
- May introduce untrusted or malicious code

**Mitigation:** Audit your configured repositories. Remove sources you no longer trust.

### 3. Flatpak and Snap Update Risks

If flatpak or snap updates are enabled, nudge will upgrade sandboxed applications alongside system packages. Risks include:

- Flatpak runtimes being upgraded unexpectedly, changing application behavior
- Snap refreshes occurring in the background and restarting running applications
- Conflicts between Flatpak/Snap versions and system library versions

**Mitigation:** Review your installed Flatpaks and Snaps. Disable flatpak/snap updates in `nudge.conf` if you manage them separately.

### 4. Snapshot Tool Risks

nudge can optionally invoke snapshot tools (timeshift, snapper, btrfs) before running updates. These tools:

- May fail silently if storage is full or the snapshot backend is misconfigured
- Do not guarantee a bootable restore point — snapshot success does not imply a safe rollback
- timeshift and snapper require correct initial setup to function

**Mitigation:** Test your snapshot and restore process before relying on it. Confirm snapshots are being created successfully after enabling this feature.

### 5. Unattended Execution

nudge runs automatically at login (XDG autostart) or on a systemd user timer schedule. If you configured `AUTO_DISMISS` with a timeout, or if a child or shared-account user clicks "Update Now" without understanding the implications, updates may proceed without informed review.

**Mitigation:** Set `ENABLED=false` on shared accounts. Do not use `AUTO_DISMISS` on production machines. Educate all account users.

### 6. Network and Download Integrity

Updates are downloaded from configured repositories over the network. While package managers verify signatures by default, network-level attacks (DNS poisoning, MITM on HTTP mirrors) could potentially interfere.

**Mitigation:** Use HTTPS mirrors where available. Keep your package manager's keyring and GPG keys up to date.

### 7. Reboot Detection

nudge detects when a kernel upgrade has been applied and prompts you to reboot. This detection compares the running kernel version against the installed kernel. If you dismiss the reboot prompt, your system is running an outdated kernel until the next reboot.

**Mitigation:** Reboot promptly after kernel upgrades. Do not defer reboots indefinitely on security-sensitive systems.

---

## What nudge Does NOT Do

- **No physical hazards** — nudge is pure software with no hardware interaction
- **No security testing** — nudge does not probe, scan, or test any system
- **No system telemetry** — nudge does not transmit usage data or update counts to any server
- **No persistent background execution** — nudge runs once at login or on a timer, performs its check, and exits; no background processes remain
- **No root persistence** — nudge does not install system-wide daemons or services
- **Limited network calls** — nudge makes outbound HTTPS requests only for connectivity probing and, if self-update is enabled, to the GitHub API (checked at most once per 24 hours); it opens no ports and accepts no inbound connections
- **No automatic updates** — nudge prompts you; it never applies updates without your explicit confirmation

---

## User Responsibility

By using nudge, you accept responsibility for:

- Reviewing available updates before accepting them
- Maintaining system backups before major upgrades
- Understanding your system's package sources and their trustworthiness
- Verifying that snapshot tools are correctly configured if you rely on them for rollback
- Configuring nudge appropriately for your environment (disable on servers, shared accounts, or critical workstations)

---

## Hierarchy of Controls

When managing any identified risk, apply controls in this order of preference:

| Priority | Control Type | Description | Example |
|----------|-------------|-------------|---------|
| 1 | **Elimination** | Remove the hazard entirely | Disable nudge on servers (`ENABLED=false`) |
| 2 | **Substitution** | Replace with something less hazardous | Use `--check-only` instead of full upgrade |
| 3 | **Engineering controls** | Isolate people from the hazard | Pre-upgrade snapshots (`SNAPSHOT_ENABLED=true`) |
| 4 | **Administrative controls** | Change the way people work | Review update preview before accepting |
| 5 | **PPE** | Protect the individual (last resort) | Maintain system backups independently |

---

## Incident Reporting

If an incident occurs while using nudge:

1. **Stop the update** if it is still running (Ctrl+C in the terminal)
2. **Do not reboot** if the upgrade failed mid-way — assess the state first
3. **Report the incident** via [GitHub Issues](https://github.com/otmof-ops/nudge/issues) or the security contact in [SECURITY.md](../.github/SECURITY.md)
4. **Document** what happened, which distribution and package manager were in use, the nudge version, and any error output

---

## Disclaimer

OFFTRACKMEDIA Studios accepts no liability for system damage, data loss, or service disruption arising from the use or misuse of nudge. Users are responsible for:

- Reviewing available updates before accepting them
- Maintaining system backups before major upgrades
- Understanding their system's package sources and their trustworthiness
- Verifying that snapshot tools are correctly configured if relying on them for rollback
- Configuring nudge appropriately for their environment
- Complying with all applicable laws and regulations in their jurisdiction

---

(c) 2026 OFFTRACKMEDIA Studios · ABN 84 290 819 896
