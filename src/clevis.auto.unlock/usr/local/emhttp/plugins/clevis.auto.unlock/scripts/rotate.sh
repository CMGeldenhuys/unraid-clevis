#!/bin/bash
# rotate.sh — re-seal the passphrase to the tang server's current signing key. Use
# after rotating tang's keys (tangd-keygen). It recovers the passphrase using the
# existing JWE (tang keeps rotated keys for decryption), then re-encrypts it pinned
# to the current primary thumbprint. If the old key is gone, it cannot recover and
# asks you to re-seal with the passphrase.
#
#   rotate.sh [tang-url]
#
# Output: {"ok":bool,"thp":...}
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-common.sh
. "$here/lib-common.sh"

emit_err() { printf '{"ok":false,"error":%s}\n' "$(jq -Rn --arg m "$1" '$m')"; exit 1; }
cleanup() { [ -n "${tmpkey:-}" ] && { shred -u "$tmpkey" 2>/dev/null || rm -f "$tmpkey"; }; }
trap cleanup EXIT

url="${1:-$(cau_tang_url)}"
cau_require clevis cryptsetup jq curl jose >/dev/null || emit_err "Required tools are missing."
[ -n "$url" ] || emit_err "No tang server URL given or configured."
cau_is_sealed || emit_err "Nothing is sealed yet."

tmpkey="$(mktemp)"; chmod 600 "$tmpkey"
clevis decrypt < "$SECRET_JWE" > "$tmpkey" 2>/dev/null \
  || emit_err "Could not recover the current secret (the old tang key may be gone). Re-seal with your passphrase instead."
[ -s "$tmpkey" ] || emit_err "Recovered an empty secret."

new_thp="$(cau_tang_thp "$url")" || emit_err "Could not reach tang at $url."
[ -n "$new_thp" ] || emit_err "Tang advertisement had no usable signing key."

tang_cfg="$(jq -nc --arg url "$url" --arg thp "$new_thp" '{url:$url,thp:$thp}')"
( umask 077; clevis encrypt tang "$tang_cfg" < "$tmpkey" > "$SECRET_JWE.new" 2>/dev/null ) \
  || { rm -f "$SECRET_JWE.new"; emit_err "Re-encryption failed."; }
clevis decrypt < "$SECRET_JWE.new" >/dev/null 2>&1 \
  || { rm -f "$SECRET_JWE.new"; emit_err "Re-sealed secret failed to decrypt back — keeping the old one."; }
mv "$SECRET_JWE.new" "$SECRET_JWE"

if [ -f "$CONFIG_FILE" ]; then
  tmp="$(mktemp)"; jq --arg thp "$new_thp" --arg url "$url" '.tang.url=$url | .tang.thp=$thp' \
    "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
fi
rm -f "/run/${PLUGIN}.health" 2>/dev/null || true

cau_notify normal "Tang key re-pinned" "Re-sealed the passphrase to the current tang key on $url."
printf '{"ok":true,"thp":%s}\n' "$(jq -Rn --arg v "$new_thp" '$v')"
