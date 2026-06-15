#!/bin/bash
# Post-install for the clevis.auto.unlock package. Runs as root, and re-runs on
# every Unraid boot (plugins are reinstalled from /boot each boot), so it MUST be
# idempotent and non-interactive. It installs the bundled dependency packages for
# the detected Unraid ABI and registers the health-check cron. It does NOT replace
# any system binary and does NOT create a placeholder keyfile.
set -uo pipefail

PLUGIN=clevis.auto.unlock
EMHTTP_DIR="/usr/local/emhttp/plugins/$PLUGIN"
PKGS_DIR="$EMHTTP_DIR/pkgs"
LOG_TAG="$PLUGIN.install"
NOTIFY="/usr/local/emhttp/webGui/scripts/notify"

log()   { logger -t "$LOG_TAG" -- "$*" 2>/dev/null; echo "> $LOG_TAG: $*"; }
alert() { log "$1"; [ -x "$NOTIFY" ] && "$NOTIFY" -e "Clevis Auto-Unlock" -s "$2" -d "$1" -i "${3:-warning}" >/dev/null 2>&1 || true; }

[ "$(id -u)" -eq 0 ] || { echo "must run as root" >&2; exit 99; }

# Never read from stdin during install — installpkg may attach a pipe, and any
# stdin-reading child (e.g. a clevis sub-tool) would hang the whole install.
exec </dev/null

# --- detect Unraid ABI variant ----------------------------------------------
if   [ -f /lib64/libcrypto.so.1.1 ]; then variant=unraid-v6
elif [ -f /lib64/libcrypto.so.3   ]; then variant=unraid-v7
else
  alert "Could not identify libcrypto ($(ls /lib64/libcrypto.* 2>/dev/null)). Aborting." \
        "Install failed" warning
  exit 1
fi
log "detected $variant"

# --- install bundled dependencies (idempotent) -------------------------------
install_pkg() {
  local p="$1"
  log "installing dependency $(basename "$p")"
  /sbin/upgradepkg --install-new --reinstall "$p" >/dev/null 2>&1 \
    || { alert "Failed to install dependency $(basename "$p"). Aborting." "Install failed" warning; exit 2; }
}

shopt -s nullglob
# jose, luksmeta and clevis are all arch-specific and tagged per variant.
variant_pkgs=("$PKGS_DIR"/*_"$variant".t?z)
[ "${#variant_pkgs[@]}" -ge 3 ] || { alert "Expected jose/luksmeta/clevis for $variant in $PKGS_DIR (found ${#variant_pkgs[@]}). Aborting." "Install failed" warning; exit 3; }
# Install jose first so libjose is present for clevis' compiled sss pin.
for p in "$PKGS_DIR"/jose-*_"$variant".t?z "$PKGS_DIR"/luksmeta-*_"$variant".t?z "$PKGS_DIR"/clevis-*_"$variant".t?z; do
  install_pkg "$p"
done
shopt -u nullglob

# --- ensure scripts / event hooks are executable -----------------------------
chmod +x "$EMHTTP_DIR"/scripts/*.sh 2>/dev/null || true
find "$EMHTTP_DIR"/event -type f -exec chmod +x {} + 2>/dev/null || true

# --- config dir + sane defaults ---------------------------------------------
install -d -m 0755 "/boot/config/plugins/$PLUGIN"
if [ ! -f "/boot/config/plugins/$PLUGIN/config.json" ] && [ -f "$EMHTTP_DIR/default.cfg" ]; then
  install -m 0644 "$EMHTTP_DIR/default.cfg" "/boot/config/plugins/$PLUGIN/config.json"
fi

# --- health-check cron (best-effort; refreshed each boot) --------------------
if [ -d /etc/cron.d ]; then
  printf '%s\n' \
    "# Clevis Auto-Unlock — tang reachability / key-thumbprint monitor" \
    "*/15 * * * * root $EMHTTP_DIR/scripts/health-check.sh >/dev/null 2>&1" \
    > /etc/cron.d/"$PLUGIN" 2>/dev/null || true
fi
if [ -x /usr/local/sbin/update_cron ]; then timeout 30 /usr/local/sbin/update_cron >/dev/null 2>&1 || true; fi

# --- sanity: confirm the expected binaries are present (do NOT execute them;
#     `clevis ...` runs its sub-tools, some of which read stdin and would hang) ---
for f in /usr/bin/clevis /usr/bin/jose /usr/bin/clevis-decrypt-tang; do
  [ -x "$f" ] || alert "Expected $f is missing after install — the bundled $variant packages may be incompatible." "Install warning" warning
done

log "plugin installed successfully ($variant)"
