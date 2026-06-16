#!/bin/bash
# lib-common.sh — shared constants and helpers for Clevis Auto-Unlock.
# Sourced by every plugin script. No side effects beyond defining vars/functions.
#
# Model: we DO NOT use `clevis luks bind` (which stores a per-device RANDOM key and
# cannot yield Unraid's single shared passphrase). Instead we seal the user's array
# passphrase as a clevis+tang JWE (secret.jwe); at boot we `clevis decrypt` it back
# to the one passphrase Unraid uses to open every encrypted device. The LUKS headers
# are never modified, so the user's own passphrase always remains as recovery.
#
# All paths/timeouts are overridable via the environment for off-Unraid testing.

# Ensure a complete PATH regardless of caller. php-fpm runs clear_env=yes, and the
# emhttpd event hooks and dcron all use a minimal PATH — so bare-name clevis/jose/
# cryptsetup/jq/curl (and clevis' own sub-pin lookup) can fail to resolve. This one
# export, in the file every script sources, covers the webGUI, boot-hook and cron contexts.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

: "${PLUGIN:=clevis.auto.unlock}"
: "${EMHTTP_DIR:=/usr/local/emhttp/plugins/$PLUGIN}"
: "${CONFIG_DIR:=/boot/config/plugins/$PLUGIN}"
: "${CONFIG_FILE:=$CONFIG_DIR/config.json}"
: "${SECRET_JWE:=$CONFIG_DIR/secret.jwe}"
: "${KEYFILE:=/root/keyfile}"
: "${DISKS_INI:=/var/local/emhttp/disks.ini}"
: "${NOTIFY_BIN:=/usr/local/emhttp/webGui/scripts/notify}"
: "${LOG_TAG:=clevis.auto.unlock}"
: "${NOTIFY_EVENT:=Clevis Auto-Unlock}"
: "${CAU_THP_ALG:=S256}"
: "${CAU_HTTP_CONNECT_TIMEOUT:=5}"
: "${CAU_HTTP_MAX_TIME:=10}"

# --- logging / notifications -------------------------------------------------

cau_log() { logger -t "$LOG_TAG" -- "$*" 2>/dev/null || true; }

# Verbose log: emitted ONLY when debug is enabled in config (see cau_debug_enabled).
# Keeps the default syslog quiet while allowing opt-in per-step/per-device boot detail.
cau_logv() { cau_debug_enabled && cau_log "$@"; }

# cau_notify <normal|warning|alert> <subject> <description>
cau_notify() {
  local level="$1" subject="$2" desc="$3"
  cau_log "[$level] $subject — $desc"
  [ -x "$NOTIFY_BIN" ] && "$NOTIFY_BIN" \
    -e "$NOTIFY_EVENT" -s "$subject" -d "$desc" -i "$level" >/dev/null 2>&1 || true
}

cau_have() { command -v "$1" >/dev/null 2>&1; }

cau_require() {
  local missing=0 c
  for c in "$@"; do cau_have "$c" || { echo "missing required command: $c" >&2; missing=1; }; done
  return "$missing"
}

# Sanitize to a positive integer with a fallback default.
cau_int() { case "$1" in ''|*[!0-9]*) printf '%s' "$2";; *) printf '%s' "$1";; esac; }

# --- config ------------------------------------------------------------------

cau_cfg() {
  local filter="$1" def="${2:-}" val
  [ -f "$CONFIG_FILE" ] || { printf '%s' "$def"; return 0; }
  val="$(jq -r "$filter // empty" "$CONFIG_FILE" 2>/dev/null)"
  [ -n "$val" ] && printf '%s' "$val" || printf '%s' "$def"
}

cau_enabled()    { [ "$(cau_cfg '.enabled' 'false')" = "true" ]; }
cau_tang_url()   { cau_cfg '.tang.url'; }
cau_pinned_thp() { cau_cfg '.tang.thp'; }
cau_unlock_mode(){ cau_cfg '.unlock_mode' 'event'; }       # event | go
cau_net_timeout(){ cau_int "$(cau_cfg '.network_timeout' '60')" 60; }
cau_is_sealed()  { [ -f "$SECRET_JWE" ]; }
cau_debug_enabled() { [ "$(cau_cfg '.debug' 'false')" = "true" ]; }  # opt-in verbose logging

# --- LUKS device discovery ---------------------------------------------------
# Emits "<name>\t<luks-device>" per encrypted Unraid device from disks.ini
# (array disks + cache/pools). Only available once emhttpd has written disks.ini.

cau_list_luks_devices() {
  [ -f "$DISKS_INI" ] || return 0
  awk -F'=' '
    /^\[/{ name=$0; gsub(/[]["]/,"",name); dev=""; sb=""; fs=""; next }
    /^device=/   { dev=$2; gsub(/"/,"",dev); next }
    /^deviceSb=/ { sb=$2;  gsub(/"/,"",sb); gsub(/^mapper\//,"",sb); next }
    /^fsType=/   { fs=$2;  gsub(/"/,"",fs);
                   if (fs ~ /^luks:/) {
                     d = (sb != "" ? sb : dev);
                     if (d != "") print name "\t/dev/" d;
                   }
                 }
  ' "$DISKS_INI"
}

cau_is_luks() { cryptsetup isLuks "$1" 2>/dev/null; }

# Does the passphrase (read from FILE) open <device>?  (no activation)
cau_pass_opens() { cryptsetup luksOpen --test-passphrase --key-file="$2" "$1" 2>/dev/null; }

# --- tang helpers ------------------------------------------------------------

# Fetch a tang advertisement (JWS) from <url>, with hard timeouts so a hung/slow
# server can never block array start indefinitely.
cau_tang_adv() {
  curl -sfg --connect-timeout "$CAU_HTTP_CONNECT_TIMEOUT" --max-time "$CAU_HTTP_MAX_TIME" \
    "${1%/}/adv"
}

# All signing-key thumbprints advertised by <url> (one per line).
cau_tang_thps() {
  local url="$1" jws jwks ver
  jws="$(cau_tang_adv "$url")" || return 1
  jwks="$(jose fmt --json="$jws" -Og payload -SyOg keys -AUo- 2>/dev/null)" || return 1
  ver="$(jose jwk use -i- -r -u verify -o- <<< "$jwks" 2>/dev/null)" || return 1
  jose jwk thp -i- -a "$CAU_THP_ALG" <<< "$ver" 2>/dev/null
}

# Primary thumbprint (first signing key) — what we pin at seal time.
cau_tang_thp() { cau_tang_thps "$1" | head -1; }

# Is <thp> among the thumbprints currently advertised by <url>?
# NB: `jose jwk thp` does NOT terminate its output with a newline, so the final
# (often only) thumbprint line is unterminated and `while read` returns non-zero on
# it — which would skip the comparison and falsely report "thp-changed". The
# `|| [ -n "$t" ]` clause processes that last newline-less line. Do not remove it.
cau_thp_advertised() {
  local thp="$1" url="$2" t
  while read -r t || [ -n "$t" ]; do [ "$t" = "$thp" ] && return 0; done < <(cau_tang_thps "$url" 2>/dev/null)
  return 1
}

# --- keyfile handling --------------------------------------------------------
# /root is tmpfs (RAM): the key never reaches persistent storage. shred on tmpfs
# is best-effort overwrite; prompt unlink + RAM reclamation is the real guarantee.
# Returns 0 if a staged keyfile was present and has now been wiped, 1 if there was
# nothing staged. Callers (e.g. the started-event hook) use this as the signal that
# WE auto-unlocked (only derive-key.sh ever stages /root/keyfile).
cau_wipe_keyfile() {
  [ -f "$KEYFILE" ] || return 1            # nothing staged
  shred -u -n1 "$KEYFILE" 2>/dev/null || rm -f "$KEYFILE"
  cau_log "wiped $KEYFILE"
  return 0                                  # a staged key was present and is now wiped
}

# Temp file for transient cleartext (e.g. a passphrase under validation), pinned to
# RAM-backed tmpfs so it never lands on persistent storage.
cau_mktemp_secret() { mktemp -p /dev/shm 2>/dev/null || mktemp; }
