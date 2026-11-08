#!/usr/bin/env bash
# Install a freshly built .deb into the current (clean) system with apt, so
# its Depends are resolved from the real Debian archive, then run the
# recipe's smoke_test(). Catches missing runtime deps before you see them.
#
#   scripts/smoke-test.sh <package> <file.deb>
set -euo pipefail
source "$(dirname "$0")/lib.sh"

name="${1:?usage: smoke-test.sh <package> <file.deb>}"
deb="$(realpath "${2:?missing .deb}")"
load_recipe "$name"
export DEBIAN_FRONTEND=noninteractive

log "installing $(basename "$deb") with apt (resolves Depends from Debian)"
apt-get install -y -qq --no-install-recommends "$deb" >/dev/null
log "smoke_test()"
smoke_test
log "smoke test passed"
