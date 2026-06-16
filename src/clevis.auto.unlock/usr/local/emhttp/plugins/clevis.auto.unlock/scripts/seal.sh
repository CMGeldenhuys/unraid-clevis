#!/bin/bash
# seal.sh — seal the array passphrase to a tang server (server-side; replaces the
# manual sudo setup). Reads the passphrase on STDIN.
#
#   seal.sh [tang-url]      passphrase on stdin
#
# We encrypt the user's actual shared passphrase as a clevis+tang JWE (no LUKS
# header is modified). At boot derive-key.sh decrypts it back to the one passphrase
# Unraid uses to open every device. Safety:
#  - the passphrase must currently open EVERY encrypted device (Unraid's single-key
#    model); otherwise we refuse, because a single keyfile could not unlock them all.
#  - the tang signing-key thumbprint is pinned, so the seal is non-interactive and a
#    rogue/MITM advertisement is rejected.
#  - the passphrase is read from stdin only — never in argv, never logged.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-common.sh
. "$here/lib-common.sh"

emit_err() { cau_log "[warning] seal failed: $1"; printf '{"ok":false,"error":%s}\n' "$(jq -Rn --arg m "$1" '$m')"; exit 1; }
cleanup() { [ -n "${tmpkey:-}" ] && { shred -u "$tmpkey" 2>/dev/null || rm -f "$tmpkey"; }; unset pass 2>/dev/null || true; }
trap cleanup EXIT

url="${1:-$(cau_tang_url)}"
cau_require clevis cryptsetup jq curl jose >/dev/null || emit_err "Required tools are missing."
[ -n "$url" ] || emit_err "No tang server URL given or configured."

pass="$(cat)"
[ -n "$pass" ] || emit_err "Empty passphrase."

tmpkey="$(cau_mktemp_secret)"; chmod 600 "$tmpkey"; printf '%s' "$pass" > "$tmpkey"

# The passphrase must open EVERY encrypted device.
total=0; opened=0; failed=""
while IFS=$'\t' read -r _name dev; do
  [ -b "$dev" ] && cau_is_luks "$dev" || continue
  total=$((total + 1))
  if cau_pass_opens "$dev" "$tmpkey"; then opened=$((opened + 1)); else failed="$failed $dev"; fi
done < <(cau_list_luks_devices)

[ "$total" -gt 0 ] || emit_err "No encrypted devices found to validate against."
[ "$opened" -eq "$total" ] || emit_err "Passphrase did not open:$failed — it must unlock ALL encrypted devices (Unraid uses one shared key)."

# Pin the primary tang signing-key thumbprint (also proves tang is reachable).
thp="$(cau_tang_thp "$url")" || emit_err "Could not reach tang at $url to compute its key thumbprint."
[ -n "$thp" ] || emit_err "Tang advertisement had no usable signing key."

mkdir -p "$CONFIG_DIR"
tang_cfg="$(jq -nc --arg url "$url" --arg thp "$thp" '{url:$url,thp:$thp}')"
( umask 077; printf '%s' "$pass" | clevis encrypt tang "$tang_cfg" > "$SECRET_JWE" 2>/dev/null ) \
  || { rm -f "$SECRET_JWE"; emit_err "clevis encrypt failed."; }

# Round-trip check: the JWE must decrypt back via tang right now.
clevis decrypt < "$SECRET_JWE" >/dev/null 2>&1 \
  || { rm -f "$SECRET_JWE"; emit_err "Sealed secret failed to decrypt back via tang — not saved."; }

cur="$([ -f "$CONFIG_FILE" ] && cat "$CONFIG_FILE" || echo '{}')"
tmp="$(mktemp)"
if ! { jq -n --arg url "$url" --arg thp "$thp" --argjson cur "$cur" \
        '$cur + {enabled:true, tang:{url:$url,thp:$thp}, unlock_mode:($cur.unlock_mode // "event"), network_timeout:($cur.network_timeout // 60)}' \
        > "$tmp" && mv "$tmp" "$CONFIG_FILE"; }; then
  rm -f "$tmp" "$SECRET_JWE"
  emit_err "Could not write config — seal rolled back."
fi
chmod 0644 "$CONFIG_FILE" 2>/dev/null || true

cau_notify normal "Array passphrase sealed to tang" \
  "Auto-unlock armed for $total device(s) via $url. Your passphrase remains your recovery key."
printf '{"ok":true,"devices":%s,"thp":%s}\n' "$total" "$(jq -Rn --arg v "$thp" '$v')"
