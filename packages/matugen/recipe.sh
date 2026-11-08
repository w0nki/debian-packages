# shellcheck shell=bash
# matugen — Material You color palette generator (used by dms for theming)

pkgname=matugen
upstream_git=https://github.com/InioX/matugen.git
homepage=https://github.com/InioX/matugen

track=tags
tag_regex='^v[0-9]+\.[0-9]+\.[0-9]+$'
pkgrel=1
arches=(amd64)

section=graphics
summary="Material You color generation tool with templates"
description="Generates a Material You color palette from an image or color and fills
in templates for GTK, Qt, terminals and other apps.

Built from upstream source; see /usr/share/doc/matugen/README.build."

build_depends=(cargo rustc pkgconf)

# matugen doesn't declare a minimum Rust version, so Debian's rustc could be
# too old for its locked dependencies at any release. Always use current stable.
rust_toolchain=stable

build() {
  ensure_rust
  cargo build --release --locked -j "$jobs"
}

package() {
  install -Dm755 target/release/matugen "$pkgdir/usr/bin/matugen"
}

smoke_test() {
  matugen --version
}
