#!/usr/bin/env bash
# Build a package on your own machine in a throwaway debian container, the
# same way CI does, then install it into a second fresh container and run its
# smoke test. Uses podman if present, otherwise docker.
#
#   scripts/local-build.sh <package> [ref]
#
# Output lands in ./out/. Add SMOKE=0 to skip the install test.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

name="${1:?usage: local-build.sh <package> [ref]}"
ref="${2:-}"
engine="$(command -v podman || command -v docker || true)"
[[ -n "$engine" ]] || die "need podman or docker"
image="docker.io/library/debian:$SUITE"
tty=(); [[ -t 0 ]] && tty=(-t)

mkdir -p "$REPO_ROOT/out"
log "building in $image"
deb="$("$engine" run --rm -i "${tty[@]}" -v "$REPO_ROOT:/work:Z" -w /work "$image" \
  bash -c 'scripts/build-package.sh "$1" "$2" /work/out | tail -n1; chown -R "$3" /work/out' \
  _ "$name" "$ref" "$(id -u):$(id -g)" | tail -n1 | tr -d '\r')"
log "built ${deb#/work/}"

if [[ "${SMOKE:-1}" == 1 ]]; then
  log "smoke test in a fresh container"
  "$engine" run --rm -i "${tty[@]}" -v "$REPO_ROOT:/work:Z" -w /work "$image" \
    bash -c 'apt-get update -qq && scripts/smoke-test.sh "$1" "$2"' _ "$name" "$deb"
fi
