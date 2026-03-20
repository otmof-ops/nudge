# Risk Assessment Framework — nudge

**OFFTRACKMEDIA Studios**
**Governing Law:** Australia (Commonwealth)

> This framework provides a structured approach to identifying, assessing, and controlling risks associated with nudge. It provides a standardized 5x5 risk matrix, a hierarchy of controls, and templates for documenting risk assessments.

---

## 1. Purpose

This document establishes the risk assessment methodology for nudge. It provides:

- A standardized 5x5 risk matrix for consistent risk evaluation
- A hierarchy of controls framework
- A step-by-step risk assessment procedure
- Templates for documenting risk assessments

---

## 2. Scope

This framework applies to:

- All components and activities identified in safety categories A-D (see [SAFETY.md](SAFETY.md))
- Technical procedures involving the nudge update manager — system modifications, package management, and sudo operations
- Any activity where incorrect application could result in system damage, data loss, or security compromise

---

## 3. Risk Matrix (5x5)

### 3.1 Likelihood Scale

| Rating | Descriptor | Definition |
|--------|-----------|------------|
| 1 | Rare | Could occur only in exceptional circumstances |
| 2 | Unlikely | Could occur but is not expected |
| 3 | Possible | Might occur — has occurred infrequently in similar contexts |
| 4 | Likely | Will probably occur in most circumstances |
| 5 | Almost Certain | Expected to occur in most circumstances |

### 3.2 Consequence Scale

| Rating | Descriptor | Definition |
|--------|-----------|------------|
| 1 | Insignificant | No system impact. Negligible inconvenience. |
| 2 | Minor | Minor service disruption. Easily recoverable. |
| 3 | Moderate | System requires manual intervention to restore. Partial data loss possible. |
| 4 | Major | System unbootable or major service failure. Significant recovery effort. |
| 5 | Catastrophic | Permanent data loss. Complete system compromise. Requires full reinstall. |

### 3.3 Risk Rating Matrix

|  | **Insignificant (1)** | **Minor (2)** | **Moderate (3)** | **Major (4)** | **Catastrophic (5)** |
|---|---|---|---|---|---|
| **Almost Certain (5)** | Medium (5) | High (10) | High (15) | Extreme (20) | Extreme (25) |
| **Likely (4)** | Low (4) | Medium (8) | High (12) | High (16) | Extreme (20) |
| **Possible (3)** | Low (3) | Medium (6) | Medium (9) | High (12) | High (15) |
| **Unlikely (2)** | Low (2) | Low (4) | Medium (6) | Medium (8) | High (10) |
| **Rare (1)** | Low (1) | Low (2) | Low (3) | Low (4) | Medium (5) |

### 3.4 Risk Response Requirements

| Risk Rating | Score Range | Required Response |
|-------------|------------|-------------------|
| **Extreme** | 20-25 | Immediate action required. Activity must not proceed without explicit risk controls and senior approval. |
| **High** | 10-16 | Senior review required. Activity must include prominent safety controls and prerequisite checks. |
| **Medium** | 5-9 | Standard controls apply. Appropriate safety notices required. |
| **Low** | 1-4 | Monitor and maintain. Standard practices sufficient. |

---

## 4. Risk Assessment Procedure

### Step 1 — Identify the Activity

Describe the activity, component, or content being assessed.

### Step 2 — Identify Hazards

List all potential hazards associated with the activity.

### Step 3 — Identify Who Could Be Harmed

Identify the people, systems, or assets that could be affected.

### Step 4 — Assess Existing Controls

Document any controls already in place.

### Step 5 — Rate the Risk

Use the risk matrix (§3) to rate likelihood and consequence.

### Step 6 — Determine Additional Controls

Apply the hierarchy of controls (see [SAFETY.md](SAFETY.md)):
1. Elimination
2. Substitution
3. Engineering controls
4. Administrative controls
5. Personal protective equipment

### Step 7 — Re-Rate the Residual Risk

Rate the risk again after applying additional controls.

### Step 8 — Document and Approve

Complete the risk assessment template (§5) and obtain appropriate approval.

### Step 9 — Implement Controls

Put the agreed controls in place before the activity proceeds.

### Step 10 — Review

Review the risk assessment at defined intervals or when conditions change.

---

## 5. Risk Assessment Template

Copy this template for each risk assessment:

```
### Risk Assessment: [ASSESSMENT_TITLE]

| Field | Value |
|-------|-------|
| **Assessment ID** | RA-[SEQUENCE] |
| **Activity** | [ACTIVITY_DESCRIPTION] |
| **Assessor** | [ASSESSOR_NAME] |
| **Date** | [ASSESSMENT_DATE] |
| **Review Date** | [REVIEW_DATE] |
| **Status** | Draft / Active / Closed |

#### Hazards Identified

| # | Hazard | Who/What at Risk | Existing Controls |
|---|--------|------------------|-------------------|
| 1 | [HAZARD] | [AT_RISK] | [CONTROLS] |

#### Risk Rating (Before Additional Controls)

| Hazard # | Likelihood | Consequence | Risk Score | Risk Rating |
|----------|-----------|-------------|-----------|-------------|
| 1 | [L] | [C] | [SCORE] | [RATING] |

#### Additional Controls

| Hazard # | Control Type | Control Description |
|----------|-------------|-------------------|
| 1 | [TYPE] | [DESCRIPTION] |

#### Residual Risk (After Additional Controls)

| Hazard # | Likelihood | Consequence | Risk Score | Risk Rating |
|----------|-----------|-------------|-----------|-------------|
| 1 | [L] | [C] | [SCORE] | [RATING] |

#### Approval

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Assessor | [NAME] | [DATE] | |
| Approver | [NAME] | [DATE] | |
```

---

## 6. Active Risk Assessments

### Risk Assessment: Unattended System Updates Causing Breakage

| Field | Value |
|-------|-------|
| **Assessment ID** | RA-001 |
| **Activity** | Full system upgrade via configured UPDATE_COMMAND |
| **Assessor** | OFFTRACKMEDIA Studios |
| **Date** | 2026-03-19 |
| **Review Date** | 2026-09-19 |
| **Status** | Active |

#### Hazards Identified

| # | Hazard | Who/What at Risk | Existing Controls |
|---|--------|------------------|-------------------|
| 1 | Full upgrade breaks GPU drivers or kernel | User's desktop environment and productivity | Update preview with priority classification |
| 2 | Upgrade fails mid-way leaving partial state | System integrity | Package manager's own transaction safety |
| 3 | User accepts without reviewing package list | System stability | PREVIEW_UPDATES=true default |

#### Risk Rating (Before Additional Controls)

| Hazard # | Likelihood | Consequence | Risk Score | Risk Rating |
|----------|-----------|-------------|-----------|-------------|
| 1 | 3 (Possible) | 4 (Major) | 12 | High |
| 2 | 2 (Unlikely) | 4 (Major) | 8 | Medium |
| 3 | 4 (Likely) | 3 (Moderate) | 12 | High |

#### Additional Controls

| Hazard # | Control Type | Control Description |
|----------|-------------|-------------------|
| 1 | Engineering | Pre-upgrade snapshot via timeshift/snapper/btrfs (SNAPSHOT_ENABLED) |
| 1 | Administrative | CRITICAL/SECURITY priority labels in update preview |
| 2 | Engineering | Reboot detection post-upgrade (REBOOT_CHECK) |
| 3 | Administrative | Default PREVIEW_UPDATES=true with priority classification |

#### Residual Risk (After Additional Controls)

| Hazard # | Likelihood | Consequence | Risk Score | Risk Rating |
|----------|-----------|-------------|-----------|-------------|
| 1 | 2 (Unlikely) | 3 (Moderate) | 6 | Medium |
| 2 | 2 (Unlikely) | 3 (Moderate) | 6 | Medium |
| 3 | 3 (Possible) | 2 (Minor) | 6 | Medium |

---

### Risk Assessment: Sudo Privilege Escalation via UPDATE_COMMAND

| Field | Value |
|-------|-------|
| **Assessment ID** | RA-002 |
| **Activity** | Execution of user-configured UPDATE_COMMAND with sudo |
| **Assessor** | OFFTRACKMEDIA Studios |
| **Date** | 2026-03-19 |
| **Review Date** | 2026-09-19 |
| **Status** | Active |

#### Hazards Identified

| # | Hazard | Who/What at Risk | Existing Controls |
|---|--------|------------------|-------------------|
| 1 | Malicious UPDATE_COMMAND injected into config file | System integrity, user data | Safe config parser (no source/eval) |
| 2 | Shared-account user triggers privileged update | System stability on multi-user machines | sudo password prompt (system-level) |

#### Risk Rating (Before Additional Controls)

| Hazard # | Likelihood | Consequence | Risk Score | Risk Rating |
|----------|-----------|-------------|-----------|-------------|
| 1 | 2 (Unlikely) | 5 (Catastrophic) | 10 | High |
| 2 | 3 (Possible) | 3 (Moderate) | 9 | Medium |

#### Additional Controls

| Hazard # | Control Type | Control Description |
|----------|-------------|-------------------|
| 1 | Engineering | Config parser uses printf -v, never eval/source (STANDARDS.md §12.1) |
| 1 | Engineering | Config file permissions checked (user-owned, not world-writable) |
| 2 | Administrative | SAFETY.md recommends ENABLED=false on shared accounts |

#### Residual Risk (After Additional Controls)

| Hazard # | Likelihood | Consequence | Risk Score | Risk Rating |
|----------|-----------|-------------|-----------|-------------|
| 1 | 1 (Rare) | 5 (Catastrophic) | 5 | Medium |
| 2 | 2 (Unlikely) | 3 (Moderate) | 6 | Medium |

---

### Risk Assessment: Network Connectivity Checks Leaking Usage Patterns

| Field | Value |
|-------|-------|
| **Assessment ID** | RA-003 |
| **Activity** | Network probe to configured NETWORK_HOST for connectivity detection |
| **Assessor** | OFFTRACKMEDIA Studios |
| **Date** | 2026-03-19 |
| **Review Date** | 2026-09-19 |
| **Status** | Active |

#### Hazards Identified

| # | Hazard | Who/What at Risk | Existing Controls |
|---|--------|------------------|-------------------|
| 1 | HTTP HEAD requests to NETWORK_HOST reveal login times | User privacy | Probe uses standard HTTP methods, no tracking headers |
| 2 | DNS resolution of NETWORK_HOST reveals nudge usage | User privacy (ISP-level) | Standard DNS, same as any package manager check |

#### Risk Rating (Before Additional Controls)

| Hazard # | Likelihood | Consequence | Risk Score | Risk Rating |
|----------|-----------|-------------|-----------|-------------|
| 1 | 3 (Possible) | 1 (Insignificant) | 3 | Low |
| 2 | 4 (Likely) | 1 (Insignificant) | 4 | Low |

#### Additional Controls

| Hazard # | Control Type | Control Description |
|----------|-------------|-------------------|
| 1 | Administrative | User can configure NETWORK_HOST to any host (e.g., local gateway) |
| 2 | Administrative | User can use OFFLINE_MODE=skip to disable network checks entirely |

#### Residual Risk (After Additional Controls)

| Hazard # | Likelihood | Consequence | Risk Score | Risk Rating |
|----------|-----------|-------------|-----------|-------------|
| 1 | 2 (Unlikely) | 1 (Insignificant) | 2 | Low |
| 2 | 2 (Unlikely) | 1 (Insignificant) | 2 | Low |

---

### Risk Assessment: Self-Update Mechanism Supply Chain Risk

| Field | Value |
|-------|-------|
| **Assessment ID** | RA-004 |
| **Activity** | Self-update check and download from GitHub Releases API |
| **Assessor** | OFFTRACKMEDIA Studios |
| **Date** | 2026-03-19 |
| **Review Date** | 2026-09-19 |
| **Status** | Active |

#### Hazards Identified

| # | Hazard | Who/What at Risk | Existing Controls |
|---|--------|------------------|-------------------|
| 1 | Compromised GitHub release serves malicious update | User system integrity | HTTPS-only API requests |
| 2 | Man-in-the-middle substitutes download payload | User system integrity | HTTPS transport encryption |
| 3 | GitHub account compromise leads to poisoned release | All nudge users | GitHub account security (2FA) |

#### Risk Rating (Before Additional Controls)

| Hazard # | Likelihood | Consequence | Risk Score | Risk Rating |
|----------|-----------|-------------|-----------|-------------|
| 1 | 1 (Rare) | 5 (Catastrophic) | 5 | Medium |
| 2 | 1 (Rare) | 5 (Catastrophic) | 5 | Medium |
| 3 | 1 (Rare) | 5 (Catastrophic) | 5 | Medium |

#### Additional Controls

| Hazard # | Control Type | Control Description |
|----------|-------------|-------------------|
| 1 | Engineering | SHA256 checksum verification of downloaded release |
| 2 | Engineering | HTTPS-only transport for all GitHub API and download requests |
| 3 | Administrative | SELF_UPDATE_CHECK=false disables self-update entirely |
| 3 | Administrative | SELF_UPDATE_CHANNEL=stable limits to tagged releases only |

#### Residual Risk (After Additional Controls)

| Hazard # | Likelihood | Consequence | Risk Score | Risk Rating |
|----------|-----------|-------------|-----------|-------------|
| 1 | 1 (Rare) | 4 (Major) | 4 | Low |
| 2 | 1 (Rare) | 4 (Major) | 4 | Low |
| 3 | 1 (Rare) | 4 (Major) | 4 | Low |

---

## 7. Review Schedule

| Review Trigger | Action Required |
|---------------|----------------|
| Scheduled review date reached | Re-assess all identified risks |
| Incident or near-miss | Immediate re-assessment of related risks |
| Change in scope, tools, or environment | Re-assess affected risks |
| New hazard identified | New risk assessment required |
| Annually | Full review of all active risk assessments |

---

(c) 2025-2026 OFFTRACKMEDIA Studios
