#!/bin/bash
# Verify pinned sources against deps.lock.
#   verify-deps.sh            verify files already in build/sources/
#   verify-deps.sh --remote   re-download each URL and check it still matches the
#                             pinned hash (supply-chain drift / takeover alarm; used
#                             by the scheduled CI job)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
lock="$repo/deps.lock"
dest="$here/sources"
mode="${1:-local}"

dl() {
  if command -v curl >/dev/null 2>&1; then curl -fsSL --retry 3 -o "$2" "$1"
  else wget -q -O "$2" "$1"; fi
}

image_digest() {  # resolve the current registry digest for a ref (best-effort)
  if command -v crane >/dev/null 2>&1; then crane digest "$1" 2>/dev/null
  elif docker buildx version >/dev/null 2>&1; then
    docker buildx imagetools inspect "$1" --format '{{.Manifest.Digest}}' 2>/dev/null
  else return 2; fi
}

rc=0
while read -r kind a b c d; do
  if [ "$kind" = "IMAGE" ]; then
    ref="$a"; pinned="$b"
    if [ "$mode" = "--remote" ]; then
      cur="$(image_digest "$ref")" || { echo "SKIP  image $ref: no digest tool (crane/buildx)"; continue; }
      if [ "$cur" = "$pinned" ]; then echo "ok    image $ref"; else
        echo "FAIL  image $ref: digest drift (pinned $pinned, now $cur)" >&2; rc=1; fi
    else
      echo "pin   image $ref @ $pinned"
    fi
    continue
  fi
  [ "$kind" = "SOURCE" ] || continue
  name="$a"; version="$b"; sha="$c"; url="$d"
  file="$dest/$(basename "$url")"
  if [ "$mode" = "--remote" ]; then
    file="$(mktemp)"
    if ! dl "$url" "$file"; then echo "FAIL  $name-$version: download error" >&2; rc=1; continue; fi
  fi
  if [ ! -f "$file" ]; then echo "MISS  $name-$version: $file not present (run fetch-sources.sh)" >&2; rc=1; continue; fi
  if echo "$sha  $file" | sha256sum -c - >/dev/null 2>&1; then
    echo "ok    $name-$version"
  else
    echo "FAIL  $name-$version: sha256 mismatch (expected $sha, got $(sha256sum "$file" | awk '{print $1}'))" >&2
    rc=1
  fi
  [ "$mode" = "--remote" ] && rm -f "$file"
done < <(grep -v '^[[:space:]]*#' "$lock")

[ "$rc" -eq 0 ] && echo "All pinned sources verified." || echo "Verification FAILED." >&2
exit "$rc"
