# context-statusline

A Claude Code statusline script that renders:

```
mode: <permission mode>          (only if not the default)
<model display name>
effort: <effortLevel from settings.json>
context: <tokens> / <ctx_max> (<pct>%)
```

- The `mode` line reflects the shift+tab permission mode (plan / accept edits / bypass / normal).
- Detects 1M-context models (e.g. `Opus 4.7 [1m]`) and scales the denominator.
- Reads `effortLevel` from `~/.claude/settings.json` (or `$CLAUDE_CONFIG_DIR/settings.json`).
- Context line is yellow; mode + effort are dim grey.

## Requirements

`python3` on `PATH`:
- macOS: ships with Xcode CLT (`xcode-select --install`) or Homebrew
- Linux: `apt install python3` / `dnf install python3` / etc.
- Windows: install from python.org or `winget install Python.Python.3` — provides a `python3` alias

## Install

1. Clone this repo somewhere stable, e.g. `~/dev/context-statusline`.
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

3. Optionally set your effort level in the same file:

```json
{ "effortLevel": "high" }
```

4. Restart Claude Code (or run `/statusline` to refresh).

## Notes

- On Windows, ANSI dim/yellow is enabled automatically via
  `ENABLE_VIRTUAL_TERMINAL_PROCESSING`.
- The script reads only the tail (~256KB) of the transcript JSONL, so it's fast
  even on long sessions.
