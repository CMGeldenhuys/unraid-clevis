#!/bin/bash
# derive-key.sh — recover the array passphrase from the sealed clevis+tang JWE and
# place it in /root/keyfile so Unraid's native array start unlocks every encrypted
# device with the single shared key. Invoked from the `starting` event hook (and the
# optional /boot/config/go early-boot path).
#
# Security:
#  - clevis verifies the tang advertisement signature against the thumbprint sealed
#    into the JWE, so a rogue/MITM tang fails closed here.
#  - the passphrase only ever lives in /root/keyfile (tmpfs/RAM), mode 0600, and is
#    shredded at the `started`/`stopping` events. It is never logged or persisted.
#  - on ANY failure no keyfile is written, so Unraid falls back to its manual
#    passphrase prompt — auto-unlock never silently weakens security.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-common.sh
. "$here/lib-common.sh"

fail() { cau_wipe_keyfile; cau_notify warning "Auto-unlock unavailable" "$1"; exit 1; }

cau_enabled || { cau_log "auto-unlock disabled in config; nothing to do"; exit 0; }
cau_is_sealed || { cau_log "no sealed secret; nothing to do"; exit 0; }
cau_require clevis cryptsetup jq curl jose || fail "Required tools are missing."

url="$(cau_tang_url)"
[ -n "$url" ] || fail "No tang server configured."

# Wait (bounded) for tang to become reachable; the network may still be coming up.
timeout="$(cau_net_timeout)"; waited=0
cau_log "auto-unlock starting (mode=$(cau_unlock_mode), tang=$url, wait<=${timeout}s)"
until cau_tang_adv "$url" >/dev/null 2>&1; do
  [ "$waited" -ge "$timeout" ] && fail "Tang server '$url' not reachable within ${timeout}s."
  sleep 2; waited=$((waited + 2))
done
cau_log "tang reachable at $url after ${waited}s"

# Recover the passphrase. Write straight to the keyfile (no command substitution,
# so the exact bytes — incl. any trailing newline — are preserved).
( umask 077; clevis decrypt < "$SECRET_JWE" > "$KEYFILE" ) \
  || fail "clevis could not recover the passphrase from tang (key changed or tang rejected)."
chmod 0600 "$KEYFILE" 2>/dev/null || true
[ -s "$KEYFILE" ] || fail "Recovered an empty passphrase."
cau_logv "recovered passphrase from sealed JWE (${SECRET_JWE##*/})"

# Best-effort validation: if disks.ini is available (event mode), confirm the key
# opens EVERY encrypted device. In early-boot 'go' mode disks.ini may not exist yet;
# we then trust clevis' decrypt and let Unraid's start do the opening.
checked=0; opened=0
while IFS=$'\t' read -r _name dev; do
  [ -b "$dev" ] && cau_is_luks "$dev" || continue
  checked=$((checked + 1))
  if cau_pass_opens "$dev" "$KEYFILE"; then
    opened=$((opened + 1)); cau_logv "device $dev: key opens OK"
  else
    cau_logv "device $dev: key did NOT open"
  fi
done < <(cau_list_luks_devices)

if [ "$checked" -gt 0 ] && [ "$opened" -ne "$checked" ]; then
  fail "Recovered key opened ${opened}/${checked} encrypted devices — refusing to stage a key that won't unlock everything."
fi

msg="Passphrase recovered from tang; the array will start automatically."
[ "$checked" -gt 0 ] && msg="Passphrase recovered from tang and validated against $checked device(s); the array will start automatically."
cau_notify normal "Array auto-unlock ready" "$msg"
cau_log "keyfile staged and validated against $checked device(s); Unraid will now open the encrypted devices"
exit 0
