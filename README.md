# context-statusline

A one line Claude Code statusline, built for macOS with a Python port for Linux and Windows. It shows the model, context usage as a percentage and as tokens over the window size, the 5 hour and 7 day rate limits, and the Fable weekly limit. The weekly reset day sits after Fable, and once it is under 24 hours away it turns into an HH:MM countdown.

![statusline showing Fable 5.1, Ctx 17% (173k/1M), 5h 25%, 7d 21%, Fable 41% 15:03](statusline.png)

Every percentage fades from bright to dark inside its band so you can see where you are without reading the number.

- 0 to 50%: bright green down to dark green
- 50 to 80%: bright yellow down to dark amber
- 80 to 100%: bright red down to dark red

The reset label is on its own blue ramp. It sits dim slate a week out and brightens to cyan as the reset gets close, so it never gets mixed up with the usage colours. The countdown is floored to whole minutes, so it changes exactly when the clock's minute rolls over. Claude Code only re-runs the statusline on events and on its `refreshInterval` timer, and that timer can't be lined up with the clock, so the 10 second interval below is what keeps the flip within a few seconds of the real minute. The usage request is still once a minute because that is tied to the cache age, not the timer.

## Where the numbers come from

Claude Code hands the statusline a JSON payload with the context usage and the 5 hour and 7 day windows. Those two only update after that session's own requests, so an idle session drifts from the others, and the payload has no Fable window at all. Out of the box the script only reads that payload, so 5h and 7d are whatever this session last saw and Fable shows `--`.

Set `CONTEXT_STATUSLINE_USAGE=1` and it reads all 3 windows from the same usage endpoint the `/usage` command uses instead. It pulls your Claude Code OAuth token out of the macOS keychain, calls `api.anthropic.com/api/oauth/usage`, and caches the response in `~/.claude/cache/usage-limits.json` for 60 seconds. Every session reads that one file, so they all print the same numbers on their next render. The refresh runs in the background so the statusline never waits on the network. If the cache is missing the 5h and 7d segments fall back to the payload and Fable shows `--` until the next refresh.

That call is a plain GET against your account, not a model request. It doesn't use tokens or count against your rate limits.

## Before you turn the usage endpoint on

1. You need a Claude Pro or Max subscription. API key, Bedrock, and Vertex accounts don't have rate limit data, so if `ANTHROPIC_API_KEY`, `CLAUDE_CODE_USE_BEDROCK`, or `CLAUDE_CODE_USE_VERTEX` is set the script never reads the keychain and those segments show `--`.
2. The usage endpoint and its `anthropic-beta` header are not documented. I pulled them out of the Claude Code binary, last checked against 2.1.263, and they can change without notice. The cache is only replaced when the response still has the `five_hour` and `seven_day` windows, so a changed endpoint leaves the old numbers in place. Once the cache is more than 10 minutes old those 3 segments go dim, so you can tell stale numbers from live ones.
3. Anthropic's terms restrict using your subscription's OAuth token outside Claude Code. This is a read only call and other usage widgets do the same thing, but it isn't officially supported, so it stays off until you turn it on.

The token is only ever held in memory. It goes to `curl` on stdin so it never shows in the process list, it is never written to disk or printed, and the cache file holds just the usage response with `600` permissions.

The bash script is macOS only. It relies on `security` for the keychain and the BSD versions of `stat` and `date`. Linux and Windows use `statusline.py`, see below.

## Requirements

`jq` and `curl`. `curl` ships with macOS and `jq` is `brew install jq`.

## Install on macOS

1. Clone this repo into `~/.claude/plugins/data/context-status`:

   ```sh
   git clone https://github.com/allen-padilla/context-statusline.git ~/.claude/plugins/data/context-status
   ```

2. Add this to `~/.claude/settings.json`:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash \"$HOME/.claude/plugins/data/context-status/statusline.sh\"",
       "padding": 0,
       "refreshInterval": 10
     }
   }
   ```

   To get the shared 5h and 7d numbers and the Fable segment, add the flag to the `env` block of the same file once you have read the section above. Claude Code passes it to the statusline on every platform.

   ```json
   {
     "env": {
       "CONTEXT_STATUSLINE_USAGE": "1"
     }
   }
   ```

3. Restart Claude Code or run `/statusline` to refresh.

`refreshInterval` re-runs the script every 10 seconds even when the window is idle. Claude Code otherwise only re-runs it on events like a new message, so without it an idle window keeps showing whatever it last rendered. Every open window reads the same 60 second cache, so they all show the same numbers within a minute and it stays one small request per minute no matter how many windows you have open. If the countdown lagging the clock by up to a minute doesn't bother you, 60 is fine here too.

## Linux and Windows

`statusline.py` prints the same line with the same colours and only needs `python3` on `PATH`. It reads the token from `~/.claude/.credentials.json` instead of the keychain, which is where Claude Code keeps it on those platforms. On Windows run it from Windows Terminal or another terminal that understands 24 bit colour.

Clone the repo the same way, then use this in `settings.json` instead. The `env` flag above works the same way here.

```json
{
  "statusLine": {
    "type": "command",
    "command": "python3 \"$HOME/.claude/plugins/data/context-status/statusline.py\"",
    "padding": 0,
    "refreshInterval": 10
  }
}
```

I only run the Mac version day to day, so if the Python one breaks on your setup open an issue with the line it printed.

## Keeping the two in sync

The colour bands and thresholds are constants at the top of both files. `check-sync.sh` runs both scripts against the same fixtures and fails if the output differs, so run it before pushing a change to either one.

```sh
./check-sync.sh
```
