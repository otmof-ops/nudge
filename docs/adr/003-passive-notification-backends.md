# ADR-003: gdbus and notify-send as passive-only backends

**Status:** Accepted
**Date:** 2026-03-19
**Decision Makers:** Jay (otmof-ops)

## Context

nudge supports five notification backends. Three are fully interactive (kdialog, zenity, dunstify) — they can display a dialog and return the user's choice (accept/defer/decline). Two are passive:

- **gdbus:** Can send D-Bus notifications with action hints, but monitoring for the user's action response requires a persistent event loop (GLib main loop or `gdbus monitor`). nudge is a run-and-exit tool, not a daemon.
- **notify-send:** Sends a one-shot notification via libnotify. No return channel for user interaction.

## Decision

gdbus and notify-send backends always set `NOTIFY_RESPONSE="declined"`. They show the notification (so the user knows updates are available) but cannot accept the user's response.

A `log_warn` message is emitted when these backends are selected, advising the user to install kdialog or zenity for interactive prompts.

## Rationale

- Adding a persistent event loop to wait for gdbus action callbacks would fundamentally change nudge's architecture from run-and-exit to daemon-like. This contradicts the core design principle.
- notify-send has no mechanism for return values — this is a fundamental limitation of the tool.
- The passive backends still provide value: users see that updates are available and can run updates manually.

## Consequences

- **Positive:** Broader compatibility — nudge works on minimal desktop environments.
- **Positive:** Architecture remains simple (run-and-exit, no daemon).
- **Negative:** Users on GNOME without zenity installed get notifications but can never accept updates through nudge.
- **Mitigation:** The warning message guides users to install an interactive backend.

## Alternatives Considered

1. **Terminal fallback prompt** — Show a `read -p` prompt in the terminal for headless/SSH use cases. Deferred as out of scope for a desktop notification tool.
2. **gdbus monitor with timeout** — Wait N seconds for an action callback. Rejected due to complexity and reliability concerns (callback delivery is not guaranteed).
