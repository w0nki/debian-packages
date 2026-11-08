#!/usr/bin/env bash
# Install a freshly built .deb into the current (clean) system with apt, so
# its Depends are resolved from the real Debian archive, then run the
# recipe's smoke_test(). Catches missing runtime deps before you see them.
#
#   scripts/smoke-test.sh <package> <file.deb>
#
# If LOCAL_DEBS_DIR is set, every .deb under it is offered to apt as a local
# repo, so a package can depend on others this repo builds (dms -> matugen).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

name="${1:?usage: smoke-test.sh <package> <file.deb>}"
deb="$(realpath "${2:?missing .deb}")"
load_recipe "$name"
export DEBIAN_FRONTEND=noninteractive

setup_extra_apt_sources
if [[ -n "${LOCAL_DEBS_DIR:-}" ]] && find "$LOCAL_DEBS_DIR" -name '*.deb' -print -quit | grep -q .; then
  # Copy to a world-readable place: apt fetches as the unprivileged _apt user.
  local_repo=/var/local/smoke-debs
  rm -rf "$local_repo" && mkdir -p "$local_repo"
  find "$LOCAL_DEBS_DIR" -name '*.deb' -exec cp -t "$local_repo" {} +
  chmod -R a+rX "$local_repo"
  command -v apt-ftparchive >/dev/null || { apt-get update -qq && apt-get install -y -qq apt-utils >/dev/null; }
  (cd "$local_repo" && apt-ftparchive packages . > Packages)
  echo "deb [trusted=yes] file:$local_repo ./" > /etc/apt/sources.list.d/local-debs.list
  log "local packages available to apt: $(find "$local_repo" -name '*.deb' -printf '%f ')"
fi
apt-get update -qq

log "installing $(basename "$deb") with apt (resolves Depends from Debian)"
apt-get install -y -qq --no-install-recommends "$deb" >/dev/null
log "smoke_test()"
smoke_test
log "smoke test passed"
