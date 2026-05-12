#!/usr/bin/env python3
"""Claude Code statusline: model + effort level + context token usage.

Reads session JSON from stdin (transcript_path, model, etc.) and the latest
usage record from the transcript JSONL to compute current context size.
Cross-platform: macOS, Linux, Windows.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path


def settings_path() -> Path:
    base = os.environ.get("CLAUDE_CONFIG_DIR")
    if base:
        return Path(base) / "settings.json"
    return Path.home() / ".claude" / "settings.json"


def read_effort() -> str:
    try:
        with settings_path().open("r", encoding="utf-8") as f:
            return json.load(f).get("effortLevel", "medium")
    except Exception:
        return "medium"


def context_max_for(model_name: str) -> int:
    lower = model_name.lower()
    if "1m" in lower:
        return 1_000_000
    return 200_000


def fmt(n: int) -> str:
    if n >= 1_000_000:
        return f"{n/1_000_000:.2f}M"
    if n >= 1_000:
        return f"{n/1_000:.1f}k"
    return str(n)


def latest_usage_total(transcript_path: str) -> int:
    if not transcript_path or not os.path.isfile(transcript_path):
        return 0
    try:
        with open(transcript_path, "rb") as f:
            try:
                f.seek(-1024 * 256, os.SEEK_END)
            except OSError:
                f.seek(0)
            tail = f.read().decode("utf-8", "replace").splitlines()
        for line in reversed(tail):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            u = (obj.get("message") or {}).get("usage") or obj.get("usage")
            if not u:
                continue
            return (
                (u.get("input_tokens", 0) or 0)
                + (u.get("cache_read_input_tokens", 0) or 0)
                + (u.get("cache_creation_input_tokens", 0) or 0)
                + (u.get("output_tokens", 0) or 0)
            )
    except Exception:
        pass
    return 0


def context_color_for(total: int, ctx_max: int) -> str:
    """Percentage-based color ramp with darkening zones and bright pops at thresholds:
      0–50%:  bright green darkening to dark green
      50%:    pops to bright yellow
      50–70%: bright yellow darkening to dark yellow
      70%:    pops to bright red
      70–100%: bright red darkening to deep red
    """
    pct = total / max(ctx_max, 1)

    if pct < 0.50:
        # green zone: bright green -> dark green
        t = pct / 0.50
        r = int(80 + (30 - 80) * t)
        g = int(220 + (100 - 220) * t)
        b = int(80 + (30 - 80) * t)
    elif pct < 0.70:
        # yellow zone: bright yellow -> dark amber
        t = (pct - 0.50) / 0.20
        r = int(255 + (180 - 255) * t)
        g = int(230 + (130 - 230) * t)
        b = int(0)
    else:
        # red zone: bright red -> deep red
        t = min((pct - 0.70) / 0.30, 1.0)
        r = int(255 + (139 - 255) * t)
        g = int(60 + (0 - 60) * t)
        b = int(60 + (0 - 60) * t)

    return f"\033[38;2;{r};{g};{b}m"


def enable_windows_ansi() -> None:
    if os.name != "nt":
        return
    try:
        import ctypes

        kernel32 = ctypes.windll.kernel32
        for handle_id in (-11, -12):  # stdout, stderr
            h = kernel32.GetStdHandle(handle_id)
            mode = ctypes.c_ulong()
            if kernel32.GetConsoleMode(h, ctypes.byref(mode)):
                kernel32.SetConsoleMode(h, mode.value | 0x0004)  # ENABLE_VIRTUAL_TERMINAL_PROCESSING
    except Exception:
        pass


def main() -> int:
    enable_windows_ansi()

    try:
        payload = json.load(sys.stdin)
    except Exception:
        payload = {}

    transcript = payload.get("transcript_path", "") or ""
    model = (payload.get("model") or {}).get("display_name", "") or ""

    effort = read_effort()
    ctx_max = context_max_for(model)
    total = latest_usage_total(transcript)

    if total:
        pct = (total / ctx_max) * 100
        tokens_line = f"{fmt(total)} / {fmt(ctx_max)} ({pct:.0f}%)"
    else:
        tokens_line = f"0 / {fmt(ctx_max)} (0%)"

    dim = "\033[2;37m"
    reset = "\033[0m"
    context_color = context_color_for(total, ctx_max)

    model_line = f"{model} {dim}| effort: {effort}{reset}"
    context_line = f"{context_color}context: {tokens_line}{reset}"

    sys.stdout.write(model_line + "\n")
    sys.stdout.write(context_line)
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
