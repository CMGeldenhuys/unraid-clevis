#!/bin/bash
# Fill the .plg template with the built package's name, version, hashes and the
# release download URL, producing the final clevis.auto.unlock.plg.
#
# Env:
#   PKG_DIR            dir containing the built clevis.auto.unlock-*.txz (default /out)
#   GITHUB_REPOSITORY  owner/repo (default CMGeldenhuys/unraid-clevis)
#   RELEASE_TAG        git tag of the release, e.g. v1.0.0 (default: derived vVERSION)
#   OUT_PLG            output path (default $PKG_DIR/clevis.auto.unlock.plg)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmpl="$here/clevis.auto.unlock.plg.tmpl"

PKG_DIR="${PKG_DIR:-/out}"
repo="${GITHUB_REPOSITORY:-CMGeldenhuys/unraid-clevis}"

pkg_path="$(find "$PKG_DIR" -maxdepth 1 -type f -name 'clevis.auto.unlock-*.txz' | head -1)"
[ -n "$pkg_path" ] || { echo "no clevis.auto.unlock-*.txz in $PKG_DIR" >&2; exit 1; }
pkg="$(basename "$pkg_path")"

# version = the X.Y.Z between name- and -arch- :  clevis.auto.unlock-1.2.3-x86_64-1.txz
version="$(printf '%s' "$pkg" | sed -E 's/^clevis\.auto\.unlock-([^-]+)-.*/\1/')"
tag="${RELEASE_TAG:-v$version}"
git_url="https://github.com/${repo}/releases/download/${tag}"
plugin_url="https://github.com/${repo}/releases/latest/download/clevis.auto.unlock.plg"
support_url="https://github.com/${repo}"

sha256="$(sha256sum "$pkg_path" | awk '{print $1}')"
md5="$(md5sum "$pkg_path" | awk '{print $1}')"

out="${OUT_PLG:-$PKG_DIR/clevis.auto.unlock.plg}"
sed \
  -e "s|--pkg-version--|${version}|g" \
  -e "s|--pkg-name--|${pkg}|g" \
  -e "s|--pkg-sha256--|${sha256}|g" \
  -e "s|--pkg-md5--|${md5}|g" \
  -e "s|--git-url--|${git_url}|g" \
  -e "s|https://github.com/CMGeldenhuys/unraid-clevis/releases/latest/download/&name;.plg|${plugin_url%/*}/\&name;.plg|g" \
  -e "s|https://github.com/CMGeldenhuys/unraid-clevis|${support_url}|g" \
  "$tmpl" > "$out"

echo "wrote $out"
echo "  version=$version tag=$tag"
echo "  pkg=$pkg"
echo "  sha256=$sha256"
echo "  md5=$md5"
echo "  git_url=$git_url"
