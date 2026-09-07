#!/usr/bin/env python3
"""Claude Code status line for Linux and Windows: model, context window, 5h / 7d rate
limits, Fable weekly limit.

Same output as statusline.sh, which is the macOS version. Percentages fade within their
band from very bright to dark, and weekly reset days sit on their own slate-to-cyan ramp.

Claude Code's statusline JSON only carries the five_hour / seven_day windows, and only as of
that session's last request, so every window comes from the usage endpoint the /usage
command reads instead. That call is cached in one shared file and refreshed in a detached
process, so every session prints the same numbers and never waits on the network. The
payload values are the fallback while the cache is missing.

Keep the constants below identical to statusline.sh and run check-sync.sh before pushing.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional, Tuple

# Band edges (percent) and RGB endpoints, bright -> dark.
GREEN_MAX = 50
YELLOW_MAX = 80
GREEN_FROM, GREEN_TO = (120, 255, 120), (0, 95, 0)
YELLOW_FROM, YELLOW_TO = (255, 255, 110), (165, 115, 0)
RED_FROM, RED_TO = (255, 110, 110), (120, 0, 0)
# Reset-day ramp, a week out -> at reset.
RESET_FROM, RESET_TO = (70, 90, 120), (110, 220, 255)
RESET_RAMP_SECONDS = 604800

USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
USAGE_TTL_SECONDS = 30
LOCK_STALE_SECONDS = 30

DIM = "\033[2m"
RESET = "\033[0m"


def config_dir() -> Path:
    return Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")


def usage_cache_path() -> Path:
    override = os.environ.get("CLAUDE_STATUSLINE_CACHE")
    return Path(override) if override else config_dir() / "cache" / "usage-limits.json"


def read_oauth() -> dict:
    """The claudeAiOauth block: the credentials file on Linux/Windows, the keychain on macOS."""
    creds_file = config_dir() / ".credentials.json"
    try:
        return json.loads(creds_file.read_text(encoding="utf-8")).get("claudeAiOauth") or {}
    except (OSError, ValueError):
        pass
    if sys.platform == "darwin":
        try:
            raw = subprocess.run(
                ["security", "find-generic-password", "-s", "Claude Code-credentials", "-w"],
                capture_output=True, text=True, timeout=5, check=True,
            ).stdout
            return json.loads(raw).get("claudeAiOauth") or {}
        except (OSError, ValueError, subprocess.SubprocessError):
            pass
    return {}


def refresh_usage(cache: Path) -> None:
    oauth = read_oauth()
    token = oauth.get("accessToken")
    expires_at = int(oauth.get("expiresAt") or 0) // 1000
    if not token or expires_at <= time.time():
        return
    request = urllib.request.Request(USAGE_URL, headers={
        "Authorization": f"Bearer {token}",
        "anthropic-beta": "oauth-2025-04-20",
        "Content-Type": "application/json",
    })
    tmp = cache.with_suffix(".json.tmp")
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            body = response.read()
        json.loads(body)
        tmp.write_bytes(body)
        os.replace(tmp, cache)
    except (OSError, ValueError):
        pass
    finally:
        tmp.unlink(missing_ok=True)


def age_seconds(path: Path) -> float | None:
    try:
        return time.time() - path.stat().st_mtime
    except OSError:
        return None


def maybe_refresh_usage(cache: Path) -> None:
    """Spawn one detached refresh when the cache is stale; never block the status line."""
    age = age_seconds(cache)
    if age is not None and age < USAGE_TTL_SECONDS:
        return
    lock = cache.with_suffix(".json.lock")
    lock_age = age_seconds(lock)
    if lock_age is not None:
        if lock_age < LOCK_STALE_SECONDS:
            return
        try:
            lock.rmdir()
        except OSError:
            return
    try:
        lock.mkdir()
    except OSError:
        return
    detach = {"creationflags": 0x00000008 | 0x00000200} if os.name == "nt" else {"start_new_session": True}
    subprocess.Popen(
        [sys.executable, __file__, "--refresh", str(cache)],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, **detach,
    )


def parse_iso_utc(value: str) -> int | None:
    """'2026-09-07T16:00:00.141715+00:00' -> epoch seconds, or None."""
    try:
        return int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp())
    except (ValueError, AttributeError):
        return None


Window = Tuple[Optional[float], Optional[int]]


def window(entry: dict | None, percent_key: str) -> Window:
    entry = entry if isinstance(entry, dict) else {}
    percent = entry.get(percent_key)
    return (float(percent) if percent is not None else None), parse_iso_utc(entry.get("resets_at") or "")


def cached_windows(cache: Path) -> Tuple[Window, Window, Window]:
    """(5h, 7d, Fable) from the usage cache; each is (None, None) when absent."""
    try:
        usage = json.loads(cache.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        usage = {}
    if not isinstance(usage, dict):
        usage = {}
    fable = next((
        limit for limit in usage.get("limits") or []
        if isinstance(limit, dict) and limit.get("kind") == "weekly_scoped"
        and ((((limit.get("scope") or {}).get("model") or {}).get("display_name") or "").lower() == "fable")
    ), None)
    return (
        window(usage.get("five_hour"), "utilization"),
        window(usage.get("seven_day"), "utilization"),
        window(fable, "percent"),
    )


def lerp(start: tuple[int, int, int], end: tuple[int, int, int], frac: float) -> str:
    frac = min(1.0, max(0.0, frac))
    return ";".join(str(int(a + frac * (b - a) + 0.5)) for a, b in zip(start, end))


def fmt_pct(label: str, pct: float | None, reset_epoch: int | None = None) -> str:
    if pct is None:
        return f"{label} {DIM}--{RESET}"
    if pct < GREEN_MAX:
        lo, hi, start, end = 0, GREEN_MAX, GREEN_FROM, GREEN_TO
    elif pct < YELLOW_MAX:
        lo, hi, start, end = GREEN_MAX, YELLOW_MAX, YELLOW_FROM, YELLOW_TO
    else:
        lo, hi, start, end = YELLOW_MAX, 100, RED_FROM, RED_TO
    out = f"{label} \033[38;2;{lerp(start, end, (pct - lo) / (hi - lo))}m{pct:.0f}%{RESET}"
    if reset_epoch is not None:
        day = datetime.fromtimestamp(reset_epoch).strftime("%a")
        secs_left = reset_epoch - int(time.time())
        out += f" \033[38;2;{lerp(RESET_FROM, RESET_TO, 1 - secs_left / RESET_RAMP_SECONDS)}m{day}{RESET}"
    return out


def main() -> None:
    if len(sys.argv) == 3 and sys.argv[1] == "--refresh":
        cache = Path(sys.argv[2])
        try:
            refresh_usage(cache)
        finally:
            try:
                cache.with_suffix(".json.lock").rmdir()
            except OSError:
                pass
        return

    try:
        payload = json.load(sys.stdin)
    except ValueError:
        payload = {}
    model = (payload.get("model") or {}).get("display_name") or "unknown"
    ctx_used = (payload.get("context_window") or {}).get("used_percentage")
    limits = payload.get("rate_limits") or {}
    five = (limits.get("five_hour") or {}).get("used_percentage")
    week = (limits.get("seven_day") or {}).get("used_percentage")
    week_reset = (limits.get("seven_day") or {}).get("resets_at")

    cache = usage_cache_path()
    cache.parent.mkdir(parents=True, exist_ok=True)
    maybe_refresh_usage(cache)
    (cache_five, _), (cache_week, cache_week_reset), (fable, fable_reset) = cached_windows(cache)
    if cache_five is not None:
        five = cache_five
    if cache_week is not None:
        week, week_reset = cache_week, cache_week_reset

    if os.name == "nt":
        sys.stdout.reconfigure(newline="")
    sys.stdout.write(" | ".join([
        f"{DIM}{model}{RESET}",
        fmt_pct("Ctx", ctx_used),
        fmt_pct("5h", five),
        fmt_pct("7d", week, int(week_reset) if week_reset is not None else None),
        fmt_pct("Fable", fable, fable_reset),
    ]))
    sys.stdout.flush()


if __name__ == "__main__":
    main()
