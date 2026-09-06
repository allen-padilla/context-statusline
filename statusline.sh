#!/bin/bash
# Claude Code status line: model, context window, 5h / 7d rate limits, Fable weekly limit.
#
# Percentages fade within their band from very bright to dark:
#   green  0-50%    yellow 50-80%    red 80-100%
#
# Claude Code's statusline JSON only carries the five_hour / seven_day windows, so the
# Fable bucket comes from the same usage endpoint the /usage command reads. That call is
# cached and refreshed in the background so the status line never waits on the network.

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "unknown"')
ctx_used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
five=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

usage_cache="$HOME/.claude/cache/usage-limits.json"
usage_ttl_seconds=60

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
    "https://api.anthropic.com/api/oauth/usage" -o "$usage_cache.tmp" \
    && mv "$usage_cache.tmp" "$usage_cache"
  rm -f "$usage_cache.tmp"
}

usage_is_stale() {
  local mtime
  mtime=$(stat -f %m "$usage_cache" 2>/dev/null) || return 0
  [ $(( $(date +%s) - mtime )) -ge "$usage_ttl_seconds" ]
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

# $1 = label, $2 = percentage (may be empty), $3 = "weekday seconds-until-reset" (optional).
# The reset day fades on a cool ramp so it never reads as usage: dim slate a week out,
# brightening to cyan as the reset gets close.
fmt_pct() {
  local label="$1" val="$2" day="${3%% *}" secs_left="${3#* }"
  if [ -z "$val" ]; then
    printf "%s \033[2m--\033[0m" "$label"
    return
  fi
  awk -v pct="$val" -v label="$label" -v day="$day" -v secs_left="${secs_left:-0}" 'BEGIN {
    if (pct < 50) {
      lo=0; hi=50
      r1=120; g1=255; b1=120   # bright green
      r2=0;   g2=95;  b2=0     # dark green
    } else if (pct < 80) {
      lo=50; hi=80
      r1=255; g1=255; b1=110   # bright yellow
      r2=165; g2=115; b2=0     # dark amber
    } else {
      lo=80; hi=100
      r1=255; g1=110; b1=110   # bright red
      r2=120; g2=0;   b2=0     # dark red
    }
    frac = (pct - lo) / (hi - lo)
    if (frac < 0) frac = 0
    if (frac > 1) frac = 1
    r = int(r1 + frac * (r2 - r1) + 0.5)
    g = int(g1 + frac * (g2 - g1) + 0.5)
    b = int(b1 + frac * (b2 - b1) + 0.5)
    printf "%s \033[38;2;%d;%d;%dm%.0f%%\033[0m", label, r, g, b, pct
    if (day != "") {
      near = 1 - secs_left / 604800
      if (near < 0) near = 0
      if (near > 1) near = 1
      dr = int(70  + near * (110 - 70)  + 0.5)   # slate  (70,90,120)
      dg = int(90  + near * (220 - 90)  + 0.5)   #   -> cyan (110,220,255)
      db = int(120 + near * (255 - 120) + 0.5)
      printf " \033[38;2;%d;%d;%dm%s\033[0m", dr, dg, db, day
    }
  }'
}

ctx_str=$(fmt_pct "Ctx" "$ctx_used")
five_str=$(fmt_pct "5h" "$five")
week_str=$(fmt_pct "7d" "$week" "$(reset_info "$week_reset")")
fable_str=$(fmt_pct "Fable" "$fable" "$(reset_info "$fable_reset")")

printf "\033[2m%s\033[0m | %s | %s | %s | %s" "$model" "$ctx_str" "$five_str" "$week_str" "$fable_str"
