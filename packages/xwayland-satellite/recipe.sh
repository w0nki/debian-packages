# shellcheck shell=bash
# xwayland-satellite — runs X11 apps on Wayland compositors that don't do it
# themselves. niri starts it automatically (on demand) when it's installed.

pkgname=xwayland-satellite
upstream_git=https://github.com/Supreeeme/xwayland-satellite.git
homepage=https://github.com/Supreeeme/xwayland-satellite

# Releases are tagged v0.8, v0.8.1, ...
track=tags
tag_regex='^v[0-9]+\.[0-9]+(\.[0-9]+)?$'
pkgrel=1
arches=(amd64)

section=x11
summary="Xwayland outside your Wayland compositor"
description="Lets X11 applications run on Wayland compositors that have no built-in
Xwayland support, such as niri. niri launches it automatically when needed.

Built from upstream source; see /usr/share/doc/xwayland-satellite/README.build."

build_depends=(cargo rustc clang pkgconf libxcb1-dev libxcb-cursor-dev)
# The actual X server it drives (needs Xwayland 23.1 or newer; trixie has 24.1).
depends=(xwayland)
# The DMS repo shipped a git build under this name.
conflicts=(xwayland-satellite-git)
replaces=(xwayland-satellite-git)

build() {
  ensure_rust
  # systemd feature: tells systemd when it's ready, for the optional user unit.
  cargo build --release --locked --features systemd -j "$jobs"
}

package() {
  install -Dm755 target/release/xwayland-satellite "$pkgdir/usr/bin/xwayland-satellite"
  install -Dm644 xwayland-satellite.man "$pkgdir/usr/share/man/man1/xwayland-satellite.1"
  # Only needed with compositors that don't launch it themselves (niri does).
  install -d "$pkgdir/usr/lib/systemd/user"
  sed 's|/usr/local/bin/|/usr/bin/|' resources/xwayland-satellite.service \
    > "$pkgdir/usr/lib/systemd/user/xwayland-satellite.service"
}

smoke_test() {
  xwayland-satellite -version
}
