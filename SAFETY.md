# nudge — Safety Information

**OFFTRACKMEDIA Studios** — ABN 84 290 819 896

> **Read this document before using nudge.** Understanding the risks associated with automated system updates is your responsibility.

---

## Safety Category: System Modification

nudge is a system update prompt. When you accept an update, it runs package management commands with elevated privileges (`sudo`). This modifies your system at the package level.

---

## Risks

### 1. Package Upgrades Can Break Your System

`apt full-upgrade` can remove packages, install new ones, and upgrade the kernel. In rare cases this can:

- Break hardware drivers (especially GPU drivers and Wi-Fi)
- Remove packages you depend on (dependency resolution conflicts)
- Require a reboot that you're not ready for (kernel upgrades)
- Fail mid-upgrade and leave your system in a partially upgraded state

**Mitigation:** Review what's being upgraded before confirming. Use `apt list --upgradable` to preview. Maintain regular backups.

### 2. PPA and Third-Party Repository Risk

If you have added PPAs or third-party apt repositories, `apt full-upgrade` will include their packages in the upgrade. These packages:

- Are not vetted by Ubuntu/Debian security teams
- May conflict with official packages
- May introduce untrusted or malicious code

**Mitigation:** Audit your sources with `apt policy`. Remove PPAs you no longer trust.

### 3. Unattended Execution

nudge runs automatically at login. If you configured `AUTO_DISMISS` with a timeout, or if a child or shared-account user clicks "Update Now" without understanding the implications, updates may proceed without informed review.

**Mitigation:** Set `ENABLED=false` on shared accounts. Do not use `AUTO_DISMISS` on production machines. Educate all account users.

### 4. Network and Download Integrity

Updates are downloaded from configured apt repositories over the network. While apt verifies package signatures by default, network-level attacks (DNS poisoning, MITM on HTTP mirrors) could potentially interfere.

**Mitigation:** Use HTTPS mirrors where available. Keep your apt keyring up to date.

---

## What nudge Does NOT Do

- **No physical hazards** — nudge is pure software with no hardware interaction
- **No security testing** — nudge does not probe, scan, or test any system
- **No data collection** — nudge does not transmit any data anywhere
- **No background execution** — nudge runs once at login, then exits
- **No root persistence** — nudge does not install system-wide daemons or services

---

## User Responsibility

By using nudge, you accept responsibility for:

- Reviewing available updates before accepting them
- Maintaining system backups before major upgrades
- Understanding your system's package sources and their trustworthiness
- Configuring nudge appropriately for your environment (disable on servers, shared accounts, or critical workstations)

---

(c) 2026 OFFTRACKMEDIA Studios · ABN 84 290 819 896
