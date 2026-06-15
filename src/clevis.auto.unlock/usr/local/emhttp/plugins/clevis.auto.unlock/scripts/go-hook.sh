#!/bin/bash
# go-hook.sh — manage the optional early-boot key-staging snippet in
# /boot/config/go. This is the fallback unlock path for hosts where the `starting`
# event fires too late for unattended auto-start: the snippet runs BEFORE emhttpd
# launches, so the keyfile is guaranteed to be present when the array auto-starts.
#
#   go-hook.sh install | remove | status
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-common.sh
. "$here/lib-common.sh"

: "${GO_FILE:=/boot/config/go}"
BEGIN="# >>> clevis.auto.unlock (early-boot unlock) >>>"
END="# <<< clevis.auto.unlock (early-boot unlock) <<<"
LINE="/usr/local/emhttp/plugins/${PLUGIN}/scripts/derive-key.sh || true"

block() { printf '%s\n%s\n%s\n' "$BEGIN" "$LINE" "$END"; }

is_installed() { [ -f "$GO_FILE" ] && grep -qF "$BEGIN" "$GO_FILE"; }

case "${1:-status}" in
  install)
    is_installed && { echo '{"ok":true,"installed":true,"changed":false}'; exit 0; }
    # Insert the block BEFORE the line that launches emhttp, else append.
    [ -f "$GO_FILE" ] || { printf '#!/bin/bash\n' > "$GO_FILE"; chmod +x "$GO_FILE"; }
    if grep -qE '(^|[[:space:]])/usr/local/sbin/emhttp' "$GO_FILE"; then
      tmp="$(mktemp)"
      awk -v b="$(block)" '
        !done && /\/usr\/local\/sbin\/emhttp/ { print b; done=1 } { print }
      ' "$GO_FILE" > "$tmp" && cat "$tmp" > "$GO_FILE" && rm -f "$tmp"
    else
      # ensure the file ends with a newline before appending our block
      [ -s "$GO_FILE" ] && [ -n "$(tail -c1 "$GO_FILE")" ] && printf '\n' >> "$GO_FILE"
      block >> "$GO_FILE"
    fi
    cau_log "installed early-boot go hook"
    echo '{"ok":true,"installed":true,"changed":true}'
    ;;
  remove)
    is_installed || { echo '{"ok":true,"installed":false,"changed":false}'; exit 0; }
    tmp="$(mktemp)"
    sed "/$(printf '%s' "$BEGIN" | sed 's/[][\.*^$/]/\\&/g')/,/$(printf '%s' "$END" | sed 's/[][\.*^$/]/\\&/g')/d" \
      "$GO_FILE" > "$tmp" && cat "$tmp" > "$GO_FILE" && rm -f "$tmp"
    cau_log "removed early-boot go hook"
    echo '{"ok":true,"installed":false,"changed":true}'
    ;;
  status)
    if is_installed; then echo '{"ok":true,"installed":true}'; else echo '{"ok":true,"installed":false}'; fi
    ;;
  *) echo '{"ok":false,"error":"usage: go-hook.sh install|remove|status"}'; exit 2;;
esac
