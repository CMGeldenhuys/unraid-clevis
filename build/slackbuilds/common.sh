#!/bin/bash
# Shared helpers for the Clevis Auto-Unlock SlackBuilds.
# Sourced by jose/luksmeta/clevis SlackBuild scripts.
set -euo pipefail

# Build tag appended to package names so they never collide with distro packages.
CAU_TAG="${CAU_TAG:-_cau}"
ARCH="${ARCH:-x86_64}"
BUILD="${BUILD:-1}"
TMP="${TMP:-/tmp/cau-build}"
OUTPUT="${OUTPUT:-/tmp/cau-output}"
SRCDIR="${SRCDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../sources" && pwd)}"
# VARIANT is unraid-v6 (OpenSSL 1.1) or unraid-v7 (OpenSSL 3); empty => noarch.
VARIANT="${VARIANT:-}"

mkdir -p "$TMP" "$OUTPUT"

# cau_extract <name> <version> => echoes the extracted source dir, cd's into it.
cau_extract() {
  local name="$1" version="$2" src
  src="$(ls "$SRCDIR/$name-$version".tar.* 2>/dev/null | head -1)"
  [ -n "$src" ] || { echo "common: source for $name-$version not found in $SRCDIR" >&2; return 2; }
  rm -rf "${TMP:?}/$name-$version"
  ( cd "$TMP" && tar --no-same-owner -xf "$src" )
  cd "$TMP/$name-$version"
}

# cau_slackdesc <pkgdir> <pkgname> <line1> [line2..]  -> writes install/slack-desc
cau_slackdesc() {
  local pkgdir="$1" pkgname="$2"; shift 2
  mkdir -p "$pkgdir/install"
  {
    printf '%s\n' "# HOWTO edit this file: keep within the |-----| ruler."
    local i
    for i in 0 1 2 3 4 5 6 7 8 9 10; do
      if [ "$#" -gt 0 ]; then printf '%s: %s\n' "$pkgname" "$1"; shift
      else printf '%s:\n' "$pkgname"; fi
    done
  } > "$pkgdir/install/slack-desc"
}

# cau_makepkg <pkgdir> <pkgname> <version> <pkgarch>
# pkgarch is x86_64 or noarch; VARIANT suffix is added for non-noarch packages.
cau_makepkg() {
  local pkgdir="$1" pkgname="$2" version="$3" pkgarch="$4" suffix=""
  [ "$pkgarch" = "noarch" ] || { [ -n "$VARIANT" ] && suffix="_${VARIANT}"; }
  # Strip binaries/libs (keep it small); ignore failures on non-ELF.
  find "$pkgdir" -type f \( -name '*.so*' -o -perm -u+x \) \
    -exec sh -c 'file "$1" 2>/dev/null | grep -q ELF && strip --strip-unneeded "$1" 2>/dev/null || true' _ {} \; || true
  # -l n: keep .so symlinks IN the package (do NOT move them into a generated
  # doinst.sh). These deps are installed from WITHIN the plugin's doinst, and
  # Unraid's installpkg holds an flock while running a doinst — so a dependency
  # that also has a doinst would deadlock the nested install. No doinst => no lock.
  ( cd "$pkgdir" && /sbin/makepkg -l n -c n \
      "$OUTPUT/${pkgname}-${version}-${pkgarch}-${BUILD}${CAU_TAG}${suffix}.txz" )
}
