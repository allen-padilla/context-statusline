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
    """Piecewise color ramp:
      0–50k:    light green
      50k–100k: light green -> medium green
      100k–120k: medium green -> yellow
      120k–180k: yellow -> red
      >180k:    red (deepens slightly toward ctx_max)
    """
    stops = [
        (0,        (144, 238, 144)),  # light green
        (50_000,   (144, 238, 144)),  # light green
        (100_000,  (60, 160, 80)),    # medium green
        (120_000,  (240, 200, 40)),   # yellow
        (180_000,  (220, 50, 50)),    # red
    ]
    if total <= stops[0][0]:
        r, g, b = stops[0][1]
    else:
        for i in range(len(stops) - 1):
            x0, c0 = stops[i]
            x1, c1 = stops[i + 1]
            if total <= x1:
                t = (total - x0) / (x1 - x0)
                r = int(c0[0] + (c1[0] - c0[0]) * t)
                g = int(c0[1] + (c1[1] - c0[1]) * t)
                b = int(c0[2] + (c1[2] - c0[2]) * t)
                break
        else:
            # past final stop — deepen red toward ctx_max
            x_last = stops[-1][0]
            span = max(ctx_max - x_last, 1)
            t = min(max((total - x_last) / span, 0.0), 1.0)
            r = int(220 + (140 - 220) * t)
            g = int(50 + (0 - 50) * t)
            b = int(50 + (10 - 50) * t)
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

    import shutil, re
    width = shutil.get_terminal_size((80, 24)).columns
    ansi_re = re.compile(r"\x1b\[[0-9;]*m")

    def visible_len(s: str) -> int:
        return len(ansi_re.sub("", s))

    def row(left: str, right: str) -> str:
        gap = max(width - visible_len(left) - visible_len(right), 1)
        return f"{left}{' ' * gap}{right}"

    model_line = f"{model} {dim}| effort: {effort}{reset}"
    context_right = f"{context_color}context: {tokens_line}{reset}"

    sys.stdout.write(model_line + "\n")
    sys.stdout.write(row("", context_right))
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
