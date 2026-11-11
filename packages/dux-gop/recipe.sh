# shellcheck shell=bash
# dux-gop (dgop) — system monitoring backend dms uses for its process list,
# CPU/GPU/memory widgets and similar

pkgname=dux-gop
upstream_git=https://github.com/duxlabs-dev/dux-gop.git
homepage=https://github.com/duxlabs-dev/dux-gop

track=tags
tag_regex='^v[0-9]+\.[0-9]+\.[0-9]+$'
pkgrel=1
arches=(amd64)

section=utils
summary="system monitoring CLI and API (dgop)"
description="Reports CPU, memory, GPU, disk, network and process information.
DankMaterialShell uses it for its system monitor widgets.

Built from upstream source; see /usr/share/doc/dux-gop/README.build."

build_depends=(golang-go make)
# Upstream's older package name; this replaces it.
provides=(dgop)
conflicts=(dgop)
replaces=(dgop)

build() {
  ensure_go
  make build \
    VERSION="$upstream_ref" \
    COMMIT="${commit:0:7}" \
    BUILD_TIME="$(date -u +%Y-%m-%d_%H:%M:%S)"
}

package() {
  install -Dm755 bin/dgop "$pkgdir/usr/bin/dgop"
}

smoke_test() {
  dgop version
}
