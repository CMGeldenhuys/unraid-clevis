#!/bin/bash
# NOLOCK
# ^ Required: this post-install calls upgradepkg/installpkg for the bundled
# dependency packages. installpkg normally runs doinst.sh while holding an flock on
# /run/lock/pkgtools/doinst.sh.lock; the nested install would then deadlock on that
# same lock. The literal token NOLOCK above tells installpkg to run us without it.
#
# Post-install for the clevis.auto.unlock package. Runs as root, and re-runs on
# every Unraid boot (plugins are reinstalled from /boot each boot), so it MUST be
# idempotent and non-interactive. It installs the bundled dependency packages for
# the detected Unraid ABI and registers the health-check cron. It does NOT replace
# any system binary and does NOT create a placeholder keyfile.
set -uo pipefail

PLUGIN=clevis.auto.unlock
EMHTTP_DIR="/usr/local/emhttp/plugins/$PLUGIN"
PKGS_DIR="$EMHTTP_DIR/pkgs"
CONFIG_DIR="/boot/config/plugins/$PLUGIN"
LOG_TAG="$PLUGIN.install"
LOGFILE="$CONFIG_DIR/install.log"
NOTIFY="/usr/local/emhttp/webGui/scripts/notify"

# NOTE: do NOT `exec </dev/null` here — installpkg runs NOLOCK scripts as
# `sed ... doinst.sh | bash`, i.e. the script is fed to bash on STDIN, so
# redirecting stdin would make bash read EOF and stop executing the script.
# Instead, redirect stdin per-command on children that might read it.

mkdir -p "$CONFIG_DIR" 2>/dev/null || true
: > "$LOGFILE" 2>/dev/null || true
# log to syslog, the install window (stdout), and a persistent file you can tail.
log()   { logger -t "$LOG_TAG" -- "$*" 2>/dev/null; echo "> $LOG_TAG: $*"; printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOGFILE" 2>/dev/null || true; }
alert() { log "$1"; [ -x "$NOTIFY" ] && "$NOTIFY" -e "Clevis Auto-Unlock" -s "$2" -d "$1" -i "${3:-warning}" >/dev/null 2>&1 || true; }

log "doinst starting (pid $$)"
[ "$(id -u)" -eq 0 ] || { echo "must run as root" >&2; exit 99; }

# --- detect Unraid ABI variant ----------------------------------------------
if   [ -f /lib64/libcrypto.so.1.1 ]; then variant=unraid-v6
elif [ -f /lib64/libcrypto.so.3   ]; then variant=unraid-v7
else
  alert "Could not identify libcrypto ($(ls /lib64/libcrypto.* 2>/dev/null)). Aborting." "Install failed" warning
  exit 1
fi
log "detected $variant"

# --- install bundled dependencies (idempotent) -------------------------------
install_pkg() {
  local p="$1"
  log "installing dependency $(basename "$p")"
  if ! timeout 180 /sbin/upgradepkg --install-new --reinstall "$p" </dev/null >>"$LOGFILE" 2>&1; then
    alert "Failed to install dependency $(basename "$p"). Aborting." "Install failed" warning
    exit 2
  fi
  log "installed $(basename "$p")"
}

shopt -s nullglob
variant_pkgs=("$PKGS_DIR"/*_"$variant".t?z)
[ "${#variant_pkgs[@]}" -ge 3 ] || { alert "Expected jose/luksmeta/clevis for $variant in $PKGS_DIR (found ${#variant_pkgs[@]}). Aborting." "Install failed" warning; exit 3; }
# jose first so libjose is present for clevis' compiled sss pin.
for p in "$PKGS_DIR"/jose-*_"$variant".t?z "$PKGS_DIR"/luksmeta-*_"$variant".t?z "$PKGS_DIR"/clevis-*_"$variant".t?z; do
  install_pkg "$p"
done
shopt -u nullglob
log "dependencies installed"

# --- ensure scripts / event hooks are executable -----------------------------
chmod +x "$EMHTTP_DIR"/scripts/*.sh 2>/dev/null || true
find "$EMHTTP_DIR"/event -type f -exec chmod +x {} + 2>/dev/null || true

# --- sane default config (config dir already created above) ------------------
if [ ! -f "$CONFIG_DIR/config.json" ] && [ -f "$EMHTTP_DIR/default.cfg" ]; then
  install -m 0644 "$EMHTTP_DIR/default.cfg" "$CONFIG_DIR/config.json"
fi

# --- health-check cron ------------------------------------------------------
# Unraid's update_cron concatenates /boot/config/plugins/*/*.cron into root's
# crontab (dcron user-crontab format: NO username field). /etc/cron.d is ignored.
printf '%s\n' \
  "# Clevis Auto-Unlock — tang reachability / key-thumbprint monitor" \
  "*/15 * * * * $EMHTTP_DIR/scripts/health-check.sh >/dev/null 2>&1" \
  > "$CONFIG_DIR/health-check.cron" 2>/dev/null || true
rm -f /etc/cron.d/"$PLUGIN" 2>/dev/null || true   # drop stale file from older versions
if [ -x /usr/local/sbin/update_cron ]; then timeout 30 /usr/local/sbin/update_cron </dev/null >/dev/null 2>&1 || true; fi
log "cron registered"

# --- sanity: confirm the expected files exist (do NOT execute clevis here;
#     `clevis ...` runs its sub-tools, some of which read stdin and would hang) ---
for f in /usr/bin/clevis /usr/bin/jose /usr/bin/clevis-decrypt-tang; do
  [ -x "$f" ] || alert "Expected $f is missing after install — the bundled $variant packages may be incompatible." "Install warning" warning
done

log "plugin installed successfully ($variant)"
