#!/bin/bash
# status.sh — emit JSON describing config + sealed state + per-device encryption for
# the webGUI. Light and offline (does not contact tang or decrypt). No secrets.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-common.sh
. "$here/lib-common.sh"

devs="[]"
while IFS=$'\t' read -r name dev; do
  is_luks=false
  { [ -b "$dev" ] && cau_is_luks "$dev"; } && is_luks=true
  devs="$(jq -c --arg name "$name" --arg dev "$dev" --argjson luks "$is_luks" \
            '. + [{name:$name, device:$dev, is_luks:$luks}]' <<< "$devs")"
done < <(cau_list_luks_devices)

tools="$(jq -nc \
  --argjson clevis "$(cau_have clevis && echo true || echo false)" \
  --argjson jose   "$(cau_have jose   && echo true || echo false)" \
  --argjson cryptsetup "$(cau_have cryptsetup && echo true || echo false)" \
  '{clevis:$clevis, jose:$jose, cryptsetup:$cryptsetup}')"

jq -nc \
  --argjson enabled "$(cau_enabled && echo true || echo false)" \
  --argjson sealed  "$(cau_is_sealed && echo true || echo false)" \
  --argjson debug   "$(cau_debug_enabled && echo true || echo false)" \
  --arg url "$(cau_tang_url)" \
  --arg thp "$(cau_pinned_thp)" \
  --arg mode "$(cau_unlock_mode)" \
  --arg timeout "$(cau_net_timeout)" \
  --argjson devices "$devs" \
  --argjson tools "$tools" \
  '{
     config: { enabled:$enabled, sealed:$sealed, debug:$debug, tang:{url:$url, thp:$thp}, unlock_mode:$mode, network_timeout:($timeout|tonumber? // 60) },
     devices: $devices,
     tools: $tools
   }'
