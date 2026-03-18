# Contributing to nudge

Copyright (c) 2026 OFFTRACKMEDIA Studios (ABN: 84 290 819 896). All rights reserved.

## Contributor License Agreement

By submitting a contribution to this repository (including but not limited to pull requests, patches, code, documentation, or any other materials), You represent, warrant, and agree to the following:

1. **Grant of Rights.** You hereby grant to OFFTRACKMEDIA Studios a perpetual, worldwide, non-exclusive, no-charge, royalty-free, irrevocable license to use, reproduce, modify, prepare derivative works of, publicly display, publicly perform, sublicense, and distribute Your contribution and any derivative works thereof, in any medium and for any purpose.

2. **Ownership Assignment.** To the maximum extent permitted by applicable law, You hereby irrevocably assign, transfer, and convey to OFFTRACKMEDIA Studios all right, title, and interest in and to Your contribution, including all Intellectual Property Rights therein. To the extent such assignment is not effective under applicable law, You grant OFFTRACKMEDIA Studios an exclusive, perpetual, irrevocable license as described in Section 1 above.

3. **Representations and Warranties.** You represent and warrant that: (a) You are the sole author of the contribution and have the legal right to grant the rights set forth herein; (b) the contribution is Your original work and does not infringe, misappropriate, or otherwise violate any Intellectual Property Rights or other rights of any third party; (c) the contribution does not contain any malicious code, viruses, or other harmful components; and (d) You are not subject to any agreement, obligation, or restriction that would prevent You from making the contribution or granting the rights described herein.

4. **No Obligation.** OFFTRACKMEDIA Studios is under no obligation to accept, merge, or use any contribution, and may reject contributions at its sole discretion.

5. **Indemnification.** You agree to indemnify and hold harmless OFFTRACKMEDIA Studios from any claims, damages, or liabilities arising from Your contribution, including any claim that Your contribution infringes a third party's Intellectual Property Rights.

## How to Contribute

1. Fork the repo and create a feature branch from `master`.
2. Follow existing code patterns and conventions (see below).
3. Run `shellcheck` on all `.sh` files — CI will enforce this.
4. Run `bash -n` syntax validation on all scripts.
5. Test on at least one supported desktop environment (KDE, GNOME, or XFCE).
6. Open a Pull Request using the provided [PR template](.github/PULL_REQUEST_TEMPLATE.md).

## Code Conventions

- **Shell dialect:** Bash (`#!/usr/bin/env bash`)
- **Strict mode:** All scripts must use `set -euo pipefail`
- **Linting:** All `.sh` files must pass `shellcheck` with zero warnings
- **Naming:** Variables use `UPPER_SNAKE_CASE`, functions use `lower_snake_case`
- **Comments:** Section dividers use `# --- Section Name ---`
- **Quoting:** Always double-quote variable expansions (`"$VAR"`, not `$VAR`)
- **Dependencies:** Prefer tools available in a standard Ubuntu/Debian install

## Project Structure

```
nudge/
├── nudge.sh          — Main script (installed to ~/.local/bin/)
├── nudge.conf        — Default configuration template
├── nudge.desktop     — XDG autostart desktop entry
├── install.sh        — Interactive installer
├── uninstall.sh      — Uninstaller
├── LICENSE           — Proprietary license notice
├── EULA/             — Full EULA text
└── .github/          — CI workflows, issue/PR templates
```

---

(c) 2026 OFFTRACKMEDIA Studios · ABN 84 290 819 896
