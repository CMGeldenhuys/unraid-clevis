#!/bin/bash
# Pre/post-remove for the clevis.auto.unlock package. Removes the bundled tools and
# the health-check cron. It deliberately does NOT remove clevis bindings from any
# disk — those live in the LUKS headers, are harmless, and removing them could risk
# lockout. Your recovery passphrase continues to unlock the array after removal.
set -uo pipefail
PLUGIN=clevis.auto.unlock
LOG_TAG="$PLUGIN.uninstall"
log() { logger -t "$LOG_TAG" -- "$*" 2>/dev/null; echo "> $LOG_TAG: $*"; }

# Stop staging any keyfile.
[ -f /root/keyfile ] && { shred -u -n1 /root/keyfile 2>/dev/null || rm -f /root/keyfile; }

# Remove bundled dependency packages (named jose/luksmeta/clevis; Unraid ships none
# of these itself, so this is safe).
for pkg in clevis luksmeta jose; do
  if ls /var/log/packages/"$pkg"-* >/dev/null 2>&1; then
    log "removing $pkg"
    /sbin/removepkg "$pkg" >/dev/null 2>&1 || true
  fi
done

# Remove the health-check cron (the flash .cron that update_cron concatenates), then
# rebuild the crontab. Also drop any stale /etc/cron.d file from older versions.
rm -f /boot/config/plugins/"$PLUGIN"/*.cron /etc/cron.d/"$PLUGIN" 2>/dev/null || true
[ -x /usr/local/sbin/update_cron ] && /usr/local/sbin/update_cron >/dev/null 2>&1 || true
if [ -f /boot/config/go ] && grep -qF ">>> clevis.auto.unlock" /boot/config/go; then
  tmp="$(mktemp)"
  sed '/>>> clevis.auto.unlock/,/<<< clevis.auto.unlock/d' /boot/config/go > "$tmp" \
    && cat "$tmp" > /boot/config/go && rm -f "$tmp"
fi

log "uninstall cleanup complete (disk bindings left intact; recovery passphrase still works)"
