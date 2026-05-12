# context-statusline

A Claude Code statusline script that renders two lines:

```
<model display name> | effort: <effortLevel>
                                                    context: <tokens> / <ctx_max> (<pct>%)
```

- **Line 1**: model name on the left, followed by ` | effort: <level>` (dim grey).
- **Line 2**: context usage right-aligned to the terminal width, colored on a
  ramp:
  - light green up to 50k tokens
  - fades to medium green by 100k
  - yellow around 120k
  - red at 180k+, deepening as you approach the model's context window
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

3. Optionally set your effort level in the same file:

   ```json
   { "effortLevel": "high" }
   ```

4. Restart Claude Code (or run `/statusline` to refresh).

## Notes

- On Windows, ANSI styling is enabled automatically via
  `ENABLE_VIRTUAL_TERMINAL_PROCESSING`.
- The script reads only the tail (~256KB) of the transcript JSONL, so it's
  fast even on long sessions.
- The right-alignment uses `shutil.get_terminal_size()`; if the terminal width
  isn't detectable it falls back to 80 columns.
