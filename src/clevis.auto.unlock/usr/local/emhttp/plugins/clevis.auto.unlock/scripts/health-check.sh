#!/bin/bash
# health-check.sh — verify the configured tang server is reachable and that the
# pinned signing-key thumbprint is still among those it advertises. Notifies only on
# state CHANGES (so the cron job doesn't spam). Prints a JSON status line.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-common.sh
. "$here/lib-common.sh"

STATE_FILE="${CAU_HEALTH_STATE:=/run/${PLUGIN}.health}"

url="$(cau_tang_url)"
[ -n "$url" ] && cau_is_sealed || { echo '{"ok":false,"reason":"not configured"}'; exit 0; }

pinned="$(cau_pinned_thp)"
reachable=false; thp_ok=false; state="unreachable"
if cau_tang_adv "$url" >/dev/null 2>&1; then
  reachable=true
  if [ -z "$pinned" ] || cau_thp_advertised "$pinned" "$url"; then
    thp_ok=true; state="ok"
  else
    state="thp-changed"
  fi
fi

prev=""; [ -f "$STATE_FILE" ] && prev="$(cat "$STATE_FILE" 2>/dev/null)"
if [ "$state" != "$prev" ]; then
  case "$state" in
    ok)          [ -n "$prev" ] && cau_notify normal  "Tang server healthy" "Tang $url is reachable and its key matches the pinned thumbprint." ;;
    unreachable) cau_notify warning "Tang server unreachable" "Cannot reach tang at $url. The array will not auto-unlock until it is back." ;;
    thp-changed) cau_notify alert  "Tang key changed!" "Tang $url no longer advertises the pinned signing key. If you did not rotate it, investigate a possible MITM. Use the rotate helper to re-pin." ;;
  esac
  printf '%s' "$state" > "$STATE_FILE" 2>/dev/null || true
fi

jq -nc --argjson reach "$reachable" --argjson ok "$thp_ok" \
      --arg url "$url" --arg pinned "$pinned" --arg state "$state" \
      '{ok:($state=="ok"), state:$state, url:$url, reachable:$reach, thp_pinned:$pinned, thp_match:$ok}'
