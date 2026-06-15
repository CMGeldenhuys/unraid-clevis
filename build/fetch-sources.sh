#!/bin/bash
# Download every SOURCE pinned in deps.lock into build/sources/ and verify its
# SHA-256. Exits non-zero on any mismatch so a poisoned mirror cannot enter the build.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
lock="$repo/deps.lock"
dest="$here/sources"
mkdir -p "$dest"

download() {
  # download <url> <out>
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$1"
  else
    echo "fetch-sources: neither curl nor wget available" >&2
    exit 2
  fi
}

rc=0
while read -r kind name version sha url; do
  [ "$kind" = "SOURCE" ] || continue
  out="$dest/$(basename "$url")"
  if [ -f "$out" ] && echo "$sha  $out" | sha256sum -c - >/dev/null 2>&1; then
    echo "ok (cached)  $name-$version"
    continue
  fi
  echo "fetching     $name-$version  <- $url"
  download "$url" "$out"
  if ! echo "$sha  $out" | sha256sum -c - >/dev/null 2>&1; then
    echo "FAIL  $name-$version: sha256 mismatch" >&2
    echo "  expected $sha" >&2
    echo "  got      $(sha256sum "$out" | awk '{print $1}')" >&2
    rm -f "$out"
    rc=1
  else
    echo "verified     $name-$version"
  fi
done < <(grep -v '^[[:space:]]*#' "$lock")

exit "$rc"
