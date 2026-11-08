# shellcheck shell=bash
# dux-search (dsearch) — file search service that powers file results in the dms launcher

pkgname=dux-search
upstream_git=https://github.com/duxlabs-dev/dux-search.git
homepage=https://github.com/duxlabs-dev/dux-search

track=tags
tag_regex='^v[0-9]+\.[0-9]+\.[0-9]+$'
pkgrel=1
arches=(amd64)

section=utils
summary="fast filesystem search service (dsearch)"
description="Indexes your files and answers search queries over a local socket.
The dms launcher uses it for file results.

Enable per user with: systemctl --user enable --now dsearch

Built from upstream source; see /usr/share/doc/dux-search/README.build."

build_depends=(golang-go make)
# Upstream's older package name.
provides=(danksearch)
conflicts=(danksearch)
replaces=(danksearch)

build() {
  ensure_go
  make build \
    VERSION="$upstream_ref" \
    COMMIT="${commit:0:7}" \
    BUILD_TIME="$(date -u +%Y-%m-%d_%H:%M:%S)"
}

package() {
  install -Dm755 bin/dsearch "$pkgdir/usr/bin/dsearch"
  # Upstream's unit points at /usr/local/bin; ours installs to /usr/bin.
  install -d "$pkgdir/usr/lib/systemd/user"
  sed 's|/usr/local/bin/dsearch|/usr/bin/dsearch|' assets/dsearch.service \
    > "$pkgdir/usr/lib/systemd/user/dsearch.service"
  install -Dm644 config.example.toml "$pkgdir/usr/share/doc/dux-search/config.example.toml"
}

smoke_test() {
  dsearch version
}
