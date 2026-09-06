#!/bin/bash
# Claude Code status line for macOS: model, context window, 5h / 7d rate limits, Fable weekly limit.
#
# Percentages fade within their band from very bright to dark:
#   green  0-50%    yellow 50-80%    red 80-100%
# Weekly reset days sit on their own slate-to-cyan ramp that brightens as the reset gets close.
#
# Claude Code's statusline JSON only carries the five_hour / seven_day windows, so the
# Fable bucket comes from the same usage endpoint the /usage command reads. That call is
# cached and refreshed in the background so the status line never waits on the network.
#
# statusline.py is the Linux / Windows port. Keep these constants identical in both files
# and run check-sync.sh before pushing.

# Band edges (percent) and RGB endpoints, bright -> dark.
GREEN_MAX=50
YELLOW_MAX=80
GREEN_FROM="120 255 120";  GREEN_TO="0 95 0"
YELLOW_FROM="255 255 110"; YELLOW_TO="165 115 0"
RED_FROM="255 110 110";    RED_TO="120 0 0"
# Reset-day ramp, a week out -> at reset.
RESET_FROM="70 90 120";    RESET_TO="110 220 255"
RESET_RAMP_SECONDS=604800

USAGE_URL="https://api.anthropic.com/api/oauth/usage"
USAGE_TTL_SECONDS=60

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "unknown"')
ctx_used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
five=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
usage_cache="${CLAUDE_STATUSLINE_CACHE:-$config_dir/cache/usage-limits.json}"

refresh_usage() {
  local creds token expires_at now
  creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null) || return
  token=$(echo "$creds" | jq -r '.claudeAiOauth.accessToken // empty')
  expires_at=$(echo "$creds" | jq -r '.claudeAiOauth.expiresAt // 0')
  now=$(date +%s)
  [ -z "$token" ] && return
  [ "$((expires_at / 1000))" -le "$now" ] && return
  curl -fsS --max-time 5 \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "Content-Type: application/json" \
    "$USAGE_URL" -o "$usage_cache.tmp" \
    && mv "$usage_cache.tmp" "$usage_cache"
  rm -f "$usage_cache.tmp"
}

usage_is_stale() {
  local mtime
  mtime=$(stat -f %m "$usage_cache" 2>/dev/null) || return 0
  [ $(( $(date +%s) - mtime )) -ge "$USAGE_TTL_SECONDS" ]
}

# One refresh at a time; a lock older than 30s is treated as abandoned.
maybe_refresh_usage() {
  local lock="$usage_cache.lock" lock_mtime
  usage_is_stale || return
  if lock_mtime=$(stat -f %m "$lock" 2>/dev/null); then
    [ $(( $(date +%s) - lock_mtime )) -lt 30 ] && return
    rm -rf "$lock"
  fi
  mkdir "$lock" 2>/dev/null || return
  ( refresh_usage; rm -rf "$lock" ) >/dev/null 2>&1 </dev/null &
  disown 2>/dev/null
}

mkdir -p "$(dirname "$usage_cache")"
maybe_refresh_usage
fable_window=$(jq -r '
  (.limits // [])[]
  | select(.kind == "weekly_scoped" and ((.scope.model.display_name // "") | ascii_downcase) == "fable")
  | "\(.percent // "") \((.resets_at // "") | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | try fromdateiso8601 catch "")"' \
  "$usage_cache" 2>/dev/null | head -n1)
fable=${fable_window%% *}
fable_reset=${fable_window#* }

# "Mon 86400" = local weekday and seconds until an epoch-seconds reset; empty if unknown.
reset_info() {
  local epoch="${1%.*}"
  [ -n "$epoch" ] || return
  printf "%s %d" "$(date -r "$epoch" +%a 2>/dev/null)" "$(( epoch - $(date +%s) ))"
}

# $1 = label, $2 = percentage (may be empty), $3 = "weekday seconds-until-reset" (optional)
fmt_pct() {
  local label="$1" val="$2" day="${3%% *}" secs_left="${3#* }"
  if [ -z "$val" ]; then
    printf "%s \033[2m--\033[0m" "$label"
    return
  fi
  awk -v pct="$val" -v label="$label" -v day="$day" -v secs_left="${secs_left:-0}" \
      -v green_max="$GREEN_MAX" -v yellow_max="$YELLOW_MAX" \
      -v green_from="$GREEN_FROM" -v green_to="$GREEN_TO" \
      -v yellow_from="$YELLOW_FROM" -v yellow_to="$YELLOW_TO" \
      -v red_from="$RED_FROM" -v red_to="$RED_TO" \
      -v reset_from="$RESET_FROM" -v reset_to="$RESET_TO" -v reset_ramp="$RESET_RAMP_SECONDS" '
  function lerp(from, to, frac,   a, b) {
    split(from, a, " "); split(to, b, " ")
    return sprintf("%d;%d;%d",
      int(a[1] + frac * (b[1] - a[1]) + 0.5),
      int(a[2] + frac * (b[2] - a[2]) + 0.5),
      int(a[3] + frac * (b[3] - a[3]) + 0.5))
  }
  function clamp(x) { return x < 0 ? 0 : (x > 1 ? 1 : x) }
  BEGIN {
    if (pct < green_max)       { lo = 0;          hi = green_max;  from = green_from;  to = green_to }
    else if (pct < yellow_max) { lo = green_max;  hi = yellow_max; from = yellow_from; to = yellow_to }
    else                       { lo = yellow_max; hi = 100;        from = red_from;    to = red_to }
    printf "%s \033[38;2;%sm%.0f%%\033[0m", label, lerp(from, to, clamp((pct - lo) / (hi - lo))), pct
    if (day != "")
      printf " \033[38;2;%sm%s\033[0m", lerp(reset_from, reset_to, clamp(1 - secs_left / reset_ramp)), day
  }'
}

ctx_str=$(fmt_pct "Ctx" "$ctx_used")
five_str=$(fmt_pct "5h" "$five")
week_str=$(fmt_pct "7d" "$week" "$(reset_info "$week_reset")")
fable_str=$(fmt_pct "Fable" "$fable" "$(reset_info "$fable_reset")")

printf "\033[2m%s\033[0m | %s | %s | %s | %s" "$model" "$ctx_str" "$five_str" "$week_str" "$fable_str"
