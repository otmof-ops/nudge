# ADR-004: flock-based locking over PID files

**Status:** Accepted
**Date:** 2026-03-19
**Decision Makers:** Jay (otmof-ops)

## Context

nudge must prevent concurrent instances — if two login triggers fire simultaneously (e.g., XDG autostart + systemd timer), only one should proceed. The two standard approaches are:

1. **PID file** — Write process ID to a file, check if the PID is still alive on next run.
2. **flock** — Use kernel-level file locking via `flock(2)`.

## Decision

Use `flock -n` (non-blocking) on a lock file at `$XDG_RUNTIME_DIR/nudge-$UID.lock`.

```bash
lock_acquire() {
    exec {LOCK_FD}>"$LOCK_FILE"
    flock -n "$LOCK_FD" || return 1
}
```

## Rationale

PID files have a well-known TOCTOU (time-of-check-time-of-use) race condition:

1. Process A reads PID file, sees PID 1234
2. Process A checks if PID 1234 is alive — it's not (stale PID file)
3. Process B starts, writes its PID to the file
4. Process A deletes the "stale" PID file and writes its own PID
5. Both processes now run concurrently

`flock` is atomic at the kernel level — there is no race window. The lock is automatically released when the process exits (even on crash/SIGKILL), eliminating stale lock concerns.

## Consequences

- **Positive:** Race-free mutual exclusion, even on slow systems or under high load.
- **Positive:** Automatic cleanup — no stale locks after crash or power loss.
- **Positive:** Simpler code — no PID parsing, no kill-0 checks, no stale lock cleanup.
- **Negative:** Requires `flock` from util-linux (universally available on Linux, not on macOS/BSD).
- **Acceptable:** nudge targets Linux desktops only, where util-linux is always present.
