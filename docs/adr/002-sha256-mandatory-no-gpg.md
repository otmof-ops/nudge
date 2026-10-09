# ADR-002: SHA256 mandatory for self-update, GPG deferred

**Status:** Superseded (GPG added in v2.0.1)
**Date:** 2026-03-19
**Superseded By:** GPG verification added alongside SHA256 — both are checked when available.
**Decision Makers:** Jay (otmof-ops)

## Context

nudge's self-update mechanism downloads release tarballs from GitHub. The integrity verification options are:

1. **SHA256 checksum** — Verifies the tarball matches the published checksum.
2. **GPG detached signature** — Cryptographically proves the release was signed by the maintainer's key.
3. **cosign (Sigstore)** — Keyless signing via OIDC identity.

SHA256 alone protects against download corruption and CDN tampering, but if an attacker compromises the GitHub release (account takeover, supply chain), they can upload a matching tarball+checksum pair. GPG or cosign would detect this.

## Original Decision (v2.0.0)

SHA256 checksum verification is mandatory. The update aborts if no `SHA256SUMS` file exists in the release or if the hash doesn't match. GPG was deferred due to:

- Key management complexity for a solo-maintainer project
- `gpg` is not universally installed on target systems
- The threat model at v2.0.0 scale (single-digit users) didn't justify the complexity

## Updated Decision (v2.0.1)

GPG signature verification is now performed when both conditions are met:

1. A `.asc` signature file exists in the release assets
2. `gpg` is installed on the user's system

If GPG is not available but a signature exists, a warning is shown. SHA256 remains mandatory regardless.

## Consequences

- **Positive:** Defense-in-depth against supply chain attacks.
- **Positive:** Graceful degradation — works without gpg installed.
- **Negative:** Maintainer must sign each release with their GPG key.
- **Negative:** Users must import the maintainer's public key for full verification.
