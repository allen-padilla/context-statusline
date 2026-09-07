#!/bin/bash
# Runs statusline.sh and statusline.py against the same fixtures and fails on any
# difference, so the macOS and Linux/Windows versions can't quietly drift apart.
set -u
cd "$(dirname "$0")"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export CLAUDE_STATUSLINE_CACHE="$work/usage.json"
failed=0

# $1 = case name, $2 = stdin JSON, $3 = cached usage JSON, $4 = text the line must contain (ANSI stripped)
run_case() {
  local name="$1" expect="${4:-}"
  printf '%s' "$2" > "$work/input.json"
  printf '%s' "$3" > "$CLAUDE_STATUSLINE_CACHE"
  bash statusline.sh < "$work/input.json" > "$work/sh.txt"
  python3 statusline.py < "$work/input.json" > "$work/py.txt"
  if cmp -s "$work/sh.txt" "$work/py.txt"; then
    if [ -n "$expect" ] && ! sed 's/\x1b\[[0-9;]*m//g' "$work/sh.txt" | grep -qF "$expect"; then
      printf 'WRONG %s\n  want: %s\n  got:  %s\n' "$name" "$expect" "$(sed 's/\x1b\[[0-9;]*m//g' "$work/sh.txt")"
      failed=1
    else
      printf 'ok    %s\n' "$name"
    fi
  else
    printf 'DRIFT %s\n  sh: %s\n  py: %s\n' "$name" "$(cat -v "$work/sh.txt")" "$(cat -v "$work/py.txt")"
    failed=1
  fi
}

now=$(date +%s)
iso_in() { python3 -c 'import sys,datetime;print(datetime.datetime.fromtimestamp(int(sys.argv[1]),datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000000+00:00"))' "$1"; }
# $1 = 5h%, $2 = 7d%, $3 = Fable%, $4 = reset epoch for the weekly windows
usage_cache() {
  local reset; reset=$(iso_in "$4")
  printf '{"five_hour":{"utilization":%s,"resets_at":"%s"},"seven_day":{"utilization":%s,"resets_at":"%s"},"limits":[{"kind":"session","percent":%s},{"kind":"weekly_all","percent":%s},{"kind":"weekly_scoped","scope":{"model":{"display_name":"Fable"}},"percent":%s,"resets_at":"%s"}]}' \
    "$1" "$(iso_in $((now + 3600)))" "$2" "$reset" "$1" "$2" "$3" "$reset"
}
# $5 = total input tokens, $6 = context window size (both optional)
payload() {
  local ctx_extra=""
  [ -n "${5:-}" ] && ctx_extra=$(printf ',"total_input_tokens":%s,"context_window_size":%s' "$5" "$6")
  printf '{"model":{"display_name":"Fable 5.1"},"context_window":{"used_percentage":%s'"$ctx_extra"'},"rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":%s},"seven_day":{"used_percentage":%s,"resets_at":%s}}}' "$1" "$2" "$((now + 3600))" "$3" "$4"
}

day_of() { python3 -c 'import sys,datetime;print(datetime.datetime.fromtimestamp(int(sys.argv[1])).strftime("%a"))' "$1"; }

run_case "cache wins"     "$(payload 7 4 18 $((now + 86400)) 74836 1000000)" "$(usage_cache 9 23 37 $((now + 2 * 86400)))" "Ctx 7% (75k/1M) | 5h 9% | 7d 23% $(day_of $((now + 2 * 86400))) | Fable 37% $(day_of $((now + 2 * 86400)))"
run_case "band edges"     "$(payload 50 80 100 $((now + 6 * 86400)) 153500 200000)" "$(usage_cache 80 100 0 $((now + 6 * 86400)))" "Ctx 50% (154k/200k)"
run_case "token sizes"    "$(payload 99 0 0 $((now + 86400)) 1300000 1000000)" "$(usage_cache 0 0 0 $((now + 86400)))" "Ctx 99% (1.3M/1M)"
run_case "few tokens"     "$(payload 0 0 0 $((now + 86400)) 512 200000)"  "$(usage_cache 0 0 0 $((now + 86400)))" "Ctx 0% (512/200k)"
run_case "week out"       "$(payload 49.6 79.4 99.5 $((now + 604800)))"  "$(usage_cache 79.4 99.5 100 $((now + 604800)))"
run_case "reset overdue"  "$(payload 12 12 12 $((now - 60)))"            "$(usage_cache 12 12 12 $((now - 60)))"
run_case "payload only"   "$(payload 7 4 18 $((now + 86400)))"           '{"limits":[]}' "5h 4% | 7d 18% $(day_of $((now + 86400))) | Fable --"
run_case "no rate limits" '{"model":{"display_name":"Sonnet 5"},"context_window":{"used_percentage":null}}' '{}' "Sonnet 5 | Ctx -- | 5h -- | 7d -- | Fable --"
run_case "empty payload"  '{}'                                            ''

exit $failed
