# nudge — ASCII Art & Branding

## The Nudge Bunny

Official mascot for the nudge project.

### Primary — Notification-Sized (with dynamic data)

Used in terminal output and dialog messages. Update counts are injected at runtime.

```text
 (\__/)
 (='.'=)  nudge: 14 updates available
 (")_(")  3 security · 1 critical
```

### Header — README and Help Screen

```text
 (\__/)
 (='.'=)  nudge 2.0.0
 (")_(")  A gentle nudge to keep your system fresh.
```

### Minimal — One-Liner for Banners

```text
nudge — a gentle reminder to update
```

### Cheeky Poke — Fun Variant

```text
  /)/)
 ( . .)
 ( づ❤
```

### Classic Sit — With Icon

```text
 (\_/)
 (•ᴗ•)
 / > 🔄
```

### README Block — With Message

```text
    (\(\
    ( -.-)  ~ you have mass updates ~
    o_(")(")
```

### Idle / No Updates

```text
 (\__/)
 (='.'=)  nudge: system is up to date
 (")_(")  nothing to do
```

### Error State

```text
 (\__/)
 (='.'=)  nudge: something went wrong
 (")_(")  see --verbose for details
```

---

## Usage

The primary mascot is rendered by `output_banner()` in `lib/output.sh`.

```bash
# Two-line message (notification style)
output_banner "nudge: 14 updates available" "3 security · 1 critical"

# Single-line message
output_banner "nudge 2.0.0"

# No message (bare bunny)
output_banner
```

---

## TUI Screens (setup.sh)

### Main Menu

```text
 (\__/)
 (='.'=)  hey! i'm nudge.
 (")_(")  what would you like to do?

  [1] Install nudge
  [2] Uninstall nudge
  [3] Configure settings
  [4] Poke schedule
  [5] Update nudge
  [6] System status
  [0] Exit

  >
```

### Poke Schedule

```text
 (\__/)
 (='.'=)  how often should i poke you?
 (")_(")  currently: every login, 45s delay

  [1] Every login (default)
  [2] Once a day
  [3] Once a week
  [4] Change delay (currently 45s)
  [5] Turn nudge OFF
  [0] Back

  >
```

### Poke Schedule (Disabled)

```text
 (\__/)
 (='.'=)  i'm currently turned off.
 (")_(")  turn me back on?

  [1] Turn nudge ON
  [0] Back

  >
```

### Update (Up to Date)

```text
 (\__/)
 (='.'=)  you're up to date!
 (")_(")  running nudge v2.0.0

  [✓] auto-update: on
  [✓] channel: stable
  [✓] source: github.com/otmof-ops/nudge
```

### Update (Available)

```text
 (\__/)
 (='.'=)  nudge v2.1.0 is available!
 (")_(")  you're on v2.0.0

  [1] Update now
  [2] Skip
  [0] Back

  >
```

### Exit

```text
 (\__/)
 (='.'=)  bye! stay fresh.
 (")_(")
```

---

(c) 2026 OFFTRACKMEDIA Studios · ABN 84 290 819 896
