# context-statusline

A Claude Code statusline script that renders two lines:

```
<model display name> | effort: <effortLevel>
context: <tokens> / <ctx_max> (<pct>%)
```

- **Line 1**: model name, followed by ` | effort: <level>` (dim grey).
- **Line 2**: context usage, colored on a percentage-based ramp:
  - 0–50%: bright green darkening to dark green
  - 50–70%: bright yellow darkening to dark amber
  - 70–100%: bright red darkening to deep red
- Detects 1M-context models (e.g. `Opus 4.7 [1m]`) and scales the denominator.
- Reads `effortLevel` from `~/.claude/settings.json` (or `$CLAUDE_CONFIG_DIR/settings.json`).

## Requirements

`python3` on `PATH`:
- macOS: ships with Xcode CLT (`xcode-select --install`) or Homebrew
- Linux: `apt install python3` / `dnf install python3` / etc.
- Windows: install from python.org or `winget install Python.Python.3` — provides a `python3` alias

No third-party dependencies — standard library only.

## Install

1. Clone this repo somewhere stable, e.g. `~/dev/context-statusline`:

   ```sh
   git clone https://github.com/allen-padilla/context-statusline.git ~/dev/context-statusline
   ```

2. Add this to `~/.claude/settings.json` (adjust the path if you cloned elsewhere):

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "python3 \"$HOME/dev/context-statusline/statusline.py\"",
       "padding": 0
     }
   }
   ```

3. Restart Claude Code (or run `/statusline` to refresh).

## Notes

- On Windows, ANSI styling is enabled automatically via
  `ENABLE_VIRTUAL_TERMINAL_PROCESSING`.
- The script reads only the tail (~256KB) of the transcript JSONL, so it's
  fast even on long sessions.
