#!/bin/bash
# Runs statusline.sh and statusline.py against the same fixtures and fails on any
# difference, so the macOS and Linux/Windows versions can't quietly drift apart.
set -u
cd "$(dirname "$0")"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export CLAUDE_STATUSLINE_CACHE="$work/usage.json"
failed=0

# $1 = case name, $2 = stdin JSON, $3 = cached usage JSON
run_case() {
  local name="$1"
  printf '%s' "$2" > "$work/input.json"
  printf '%s' "$3" > "$CLAUDE_STATUSLINE_CACHE"
  bash statusline.sh < "$work/input.json" > "$work/sh.txt"
  python3 statusline.py < "$work/input.json" > "$work/py.txt"
  if cmp -s "$work/sh.txt" "$work/py.txt"; then
    printf 'ok    %s\n' "$name"
  else
    printf 'DRIFT %s\n  sh: %s\n  py: %s\n' "$name" "$(cat -v "$work/sh.txt")" "$(cat -v "$work/py.txt")"
    failed=1
  fi
}

now=$(date +%s)
iso_in() { python3 -c 'import sys,datetime;print(datetime.datetime.fromtimestamp(int(sys.argv[1]),datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000000+00:00"))' "$1"; }
fable_cache() {
  printf '{"limits":[{"kind":"session","percent":5},{"kind":"weekly_all","percent":19},{"kind":"weekly_scoped","scope":{"model":{"display_name":"Fable"}},"percent":%s,"resets_at":"%s"}]}' "$1" "$(iso_in "$2")"
}
payload() {
  printf '{"model":{"display_name":"Fable 5.1"},"context_window":{"used_percentage":%s},"rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":%s},"seven_day":{"used_percentage":%s,"resets_at":%s}}}' "$1" "$2" "$((now + 3600))" "$3" "$4"
}

run_case "typical"        "$(payload 7 4 18 $((now + 86400)))"           "$(fable_cache 37 $((now + 86400)))"
run_case "band edges"     "$(payload 50 80 100 $((now + 6 * 86400)))"    "$(fable_cache 0 $((now + 6 * 86400)))"
run_case "week out"       "$(payload 49.6 79.4 99.5 $((now + 604800)))"  "$(fable_cache 100 $((now + 604800)))"
run_case "reset overdue"  "$(payload 12 12 12 $((now - 60)))"            "$(fable_cache 12 $((now - 60)))"
run_case "no fable"       "$(payload 12 12 12 $((now + 86400)))"         '{"limits":[]}'
run_case "no rate limits" '{"model":{"display_name":"Sonnet 5"},"context_window":{"used_percentage":null}}' '{}'
run_case "empty payload"  '{}'                                            ''

exit $failed
