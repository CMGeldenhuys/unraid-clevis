#!/bin/bash
# Build the bundled dependency packages for one Unraid ABI variant.
# Run inside a vbatts/slackware build container (toolchain installed by Dockerfile).
#
#   VARIANT=unraid-v6|unraid-v7   ABI tag added to per-arch package names
#   OUTPUT=/out                   where .txz packages are written
# Builds jose, luksmeta and clevis for the given variant (all are arch-specific).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
export VARIANT="${VARIANT:?set VARIANT=unraid-v6|unraid-v7}"
export OUTPUT="${OUTPUT:-/out}"
export SRCDIR="${SRCDIR:-$here/sources}"
export TMP="${TMP:-/tmp/cau-build}"
mkdir -p "$OUTPUT" "$TMP"

echo "==> verifying pinned sources"
"$here/verify-deps.sh"

echo "==> building jansson (static, build-only) into /usr"
jsrc="$(ls "$SRCDIR"/jansson-*.tar.* | head -1)"
( cd "$TMP" && rm -rf jansson-build && mkdir jansson-build \
  && tar --no-same-owner -xf "$jsrc" -C jansson-build --strip-components=1 \
  && cd jansson-build \
  && ./configure --prefix=/usr --libdir=/usr/lib64 \
       --enable-static --disable-shared --with-pic >/dev/null \
  && make >/dev/null && make install >/dev/null )
echo "    jansson static installed: $(ls /usr/lib64/libjansson.a)"

echo "==> building jose ($VARIANT)"
"$here/slackbuilds/jose/jose.SlackBuild"
# Install jose into the build env so clevis' meson can resolve dependency('jose').
/sbin/installpkg "$OUTPUT"/jose-*.txz >/dev/null

echo "==> building luksmeta ($VARIANT)"
"$here/slackbuilds/luksmeta/luksmeta.SlackBuild"
# Install luksmeta so clevis' meson resolves dependency('luksmeta') and builds the
# clevis-luks-* commands.
/sbin/installpkg "$OUTPUT"/luksmeta-*.txz >/dev/null

echo "==> building clevis ($VARIANT)"
"$here/slackbuilds/clevis/clevis.SlackBuild"

echo "==> packages produced:"
ls -l "$OUTPUT"

echo "==> verifying shipped libjose has NO external libjansson dependency"
jpkg="$(ls "$OUTPUT"/jose-*.txz | head -1)"
tmpv="$(mktemp -d)"; tar xf "$jpkg" -C "$tmpv"
if ldd "$tmpv"/usr/lib64/libjose.so* 2>/dev/null | grep -q jansson; then
  echo "    FAIL: libjose still links libjansson dynamically" >&2
  ldd "$tmpv"/usr/lib64/libjose.so* | grep jansson >&2
  rm -rf "$tmpv"; exit 1
fi
echo "    OK: jansson is statically absorbed"
echo "    libjose external deps:"; ldd "$tmpv"/usr/lib64/libjose.so* | sed 's/^/      /'
rm -rf "$tmpv"
