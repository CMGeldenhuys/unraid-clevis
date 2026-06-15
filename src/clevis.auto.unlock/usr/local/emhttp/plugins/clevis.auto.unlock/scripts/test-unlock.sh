#!/bin/bash
# test-unlock.sh — dry run. Decrypt the sealed passphrase from tang and confirm it
# opens every encrypted device, WITHOUT activating any device and WITHOUT staging
# /root/keyfile. Validates auto-unlock before a reboot.
#
# Output: {"ok":bool,"results":[{device,opens}]}
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-common.sh
. "$here/lib-common.sh"

cau_require clevis cryptsetup jq >/dev/null || { echo '{"ok":false,"error":"missing tools"}'; exit 1; }
cau_is_sealed || { echo '{"ok":false,"error":"no sealed secret — seal the passphrase first"}'; exit 0; }

tmpkey="$(cau_mktemp_secret)"; chmod 600 "$tmpkey"
trap 'shred -u "$tmpkey" 2>/dev/null || rm -f "$tmpkey"' EXIT

if ! clevis decrypt < "$SECRET_JWE" > "$tmpkey" 2>/dev/null; then
  echo '{"ok":false,"error":"tang decrypt failed — server unreachable or key changed"}'; exit 0
fi

results="[]"; total=0
while IFS=$'\t' read -r _name dev; do
  [ -b "$dev" ] && cau_is_luks "$dev" || continue
  total=$((total + 1))
  opens=false; cau_pass_opens "$dev" "$tmpkey" && opens=true
  results="$(jq -c --arg d "$dev" --argjson o "$opens" '. + [{device:$d, opens:$o}]' <<< "$results")"
done < <(cau_list_luks_devices)

ok=false
[ "$total" -gt 0 ] && jq -e 'all(.[]; .opens)' <<< "$results" >/dev/null 2>&1 && ok=true
jq -nc --argjson ok "$ok" --argjson res "$results" '{ok:$ok, results:$res}'
