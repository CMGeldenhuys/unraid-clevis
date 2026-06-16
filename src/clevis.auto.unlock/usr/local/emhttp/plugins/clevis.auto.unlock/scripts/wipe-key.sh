#!/bin/bash
# wipe-key.sh — securely remove the staged /root/keyfile. Invoked from the
# `started` and `stopping` event hooks (and safe to run any time).
#
# The optional context arg ("started"|"stopping") lets us log a definitive
# "array unlocked" line at the right moment: by the `started` event the array is
# mounted, so a staged keyfile having been present means WE auto-unlocked it
# (only derive-key.sh ever stages /root/keyfile). A manual passphrase unlock
# stages nothing, so no false positive. syslog-only — derive-key already
# GUI-notifies "ready"; we don't want a second popup.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-common.sh
. "$here/lib-common.sh"

ctx="${1:-}"   # started | stopping | "" (manual/legacy)

if cau_wipe_keyfile; then
  # A staged keyfile was present and is now wiped (cau_wipe_keyfile logged the wipe).
  if [ "$ctx" = "started" ] && cau_enabled && cau_is_sealed; then
    cau_log "array unlocked via clevis+tang; staged key wiped"
  fi
else
  # Nothing was staged: a manual unlock, or auto-unlock disabled/forgotten.
  [ "$ctx" = "started" ] && cau_logv "started event: no staged key present (manual unlock or auto-unlock disabled)"
fi
exit 0
