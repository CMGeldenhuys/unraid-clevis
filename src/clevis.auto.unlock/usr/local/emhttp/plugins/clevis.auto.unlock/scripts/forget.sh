#!/bin/bash
# forget.sh — remove the sealed passphrase and disable auto-unlock. Does NOT touch
# any LUKS header, so disk encryption and your recovery passphrase are unchanged;
# you simply enter the passphrase manually at the next boot.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-common.sh
. "$here/lib-common.sh"

rm -f "$SECRET_JWE"
if [ -f "$CONFIG_FILE" ]; then
  tmp="$(mktemp)"; jq '.enabled=false' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
fi
cau_wipe_keyfile
rm -f "/run/${PLUGIN}.health" 2>/dev/null || true
cau_notify normal "Auto-unlock disabled" \
  "Removed the sealed passphrase. Disk encryption is unchanged; the array will ask for the passphrase manually."
echo '{"ok":true}'
