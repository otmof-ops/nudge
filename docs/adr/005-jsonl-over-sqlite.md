# ADR-005: JSONL for history over SQLite

**Status:** Accepted
**Date:** 2026-03-19
**Decision Makers:** Jay (otmof-ops)

## Context

nudge records an audit trail of each run — timestamp, package manager, update counts, user response, exit code, packages, etc. Storage options considered:

1. **SQLite** — Structured, queryable, ACID-compliant.
2. **JSONL (JSON Lines)** — One JSON object per line, append-only, plain text.
3. **CSV** — Simple but no nested data support (packages array).

## Decision

Use JSONL format at `~/.local/share/nudge/history.jsonl` with automatic rotation at 500 lines (configurable via `HISTORY_MAX_LINES`).

## Rationale

- **Zero dependencies:** JSONL needs no external libraries. SQLite would require `sqlite3` CLI or a compiled extension — an unacceptable dependency for a bash script.
- **Human-readable:** Users can inspect history with `cat`, `tail`, `jq`, or any text editor.
- **Append-only:** Each run appends one line. No schema migrations, no database corruption risk.
- **Rotation is trivial:** `tail -n $max > tmp && mv tmp file` — atomic with the write-then-rename pattern.
- **Machine-parseable:** `nudge --history --json` dumps raw JSONL; external tools can process it with `jq`.

## Tradeoffs

- **Queryability:** JSONL cannot be efficiently queried by arbitrary fields. The `--since` filter requires scanning every line. At 500 lines maximum, this is negligible.
- **Concurrency:** No file-level locking on history writes. mitigated by flock-based instance locking — only one nudge runs at a time.
- **Schema evolution:** Adding new fields to JSONL records is forward-compatible (new fields are simply present in newer records). Removing or renaming fields requires reader awareness. Acceptable at this scale.

## Consequences

- **Positive:** No runtime dependency beyond bash and coreutils.
- **Positive:** History is portable — copy the file to another machine and it works.
- **Positive:** Easy debugging — `tail -1 ~/.local/share/nudge/history.jsonl | jq .`
- **Negative:** No indexed queries — scanning is O(n) on the file. Mitigated by 500-line rotation cap.
- **Negative:** No transactional guarantees on append. Mitigated by atomic write pattern for rotation.
