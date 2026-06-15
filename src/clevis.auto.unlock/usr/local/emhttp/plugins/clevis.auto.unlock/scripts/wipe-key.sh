#!/bin/bash
# wipe-key.sh — securely remove the staged /root/keyfile. Invoked from the
# `started` and `stopping` event hooks (and safe to run any time).
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-common.sh
. "$here/lib-common.sh"
cau_wipe_keyfile
