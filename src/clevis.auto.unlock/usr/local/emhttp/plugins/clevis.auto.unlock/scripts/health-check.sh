#!/bin/bash
# health-check.sh — report the tang server's status for the webGUI and (via cron)
# notify on changes. States:
#   unconfigured  no tang URL set
#   unreachable   URL set but /adv did not respond
#   reachable     URL set & reachable, nothing sealed yet (no key to compare)
#   ok            sealed & the pinned signing key is still advertised
#   thp-changed   sealed but the pinned key is no longer advertised (rotation or MITM)
# Notifications fire only once per state CHANGE and only once a secret is sealed.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-common.sh
. "$here/lib-common.sh"

STATE_FILE="${CAU_HEALTH_STATE:=/run/${PLUGIN}.health}"

url="$(cau_tang_url)"
[ -n "$url" ] || { echo '{"ok":false,"state":"unconfigured","reason":"no tang server configured"}'; exit 0; }

pinned="$(cau_pinned_thp)"
reachable=false; thp_ok=false; state="unreachable"
if cau_tang_adv "$url" >/dev/null 2>&1; then
  reachable=true
  if [ -z "$pinned" ]; then
    state="reachable"            # up, but nothing pinned/sealed yet
  elif cau_thp_advertised "$pinned" "$url"; then
    thp_ok=true; state="ok"
  else
    state="thp-changed"
  fi
fi

# Notify only on transitions, and only when a secret is actually sealed (avoid noise
# while the user is still configuring).
if cau_is_sealed; then
  prev=""; [ -f "$STATE_FILE" ] && prev="$(cat "$STATE_FILE" 2>/dev/null)"
  if [ "$state" != "$prev" ]; then
    case "$state" in
      ok)          [ -n "$prev" ] && cau_notify normal  "Tang server healthy" "Tang $url is reachable and its key matches the pinned thumbprint." ;;
      unreachable) cau_notify warning "Tang server unreachable" "Cannot reach tang at $url. The array will not auto-unlock until it is back." ;;
      thp-changed) cau_notify alert  "Tang key changed!" "Tang $url no longer advertises the pinned signing key. If you did not rotate it, investigate a possible MITM. Use the rotate helper to re-pin." ;;
    esac
    printf '%s' "$state" > "$STATE_FILE" 2>/dev/null || true
  fi
fi

ok=false; { [ "$state" = "ok" ] || [ "$state" = "reachable" ]; } && ok=true
jq -nc --argjson ok "$ok" --argjson reach "$reachable" --argjson match "$thp_ok" \
      --arg url "$url" --arg pinned "$pinned" --arg state "$state" \
      '{ok:$ok, state:$state, url:$url, reachable:$reach, thp_pinned:$pinned, thp_match:$match}'
