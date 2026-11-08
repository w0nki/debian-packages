# shellcheck shell=bash
# niri — scrollable-tiling Wayland compositor
# Packaging notes from upstream: docs/wiki/Packaging-niri.md in the niri repo.

pkgname=niri
upstream_git=https://github.com/niri-wm/niri.git
homepage=https://github.com/niri-wm/niri

# Stable releases are tagged vYY.MM or vYY.MM.N
track=tags
tag_regex='^v[0-9]+\.[0-9]+(\.[0-9]+)?$'

# Bump when you change this recipe without upstream changing; forces a rebuild.
pkgrel=1
# Add arm64 here to also build on GitHub's arm runners.
arches=(amd64)

section=x11
summary="scrollable-tiling Wayland compositor"
description="Windows are arranged in columns on an infinite strip going to the right.
Opening a new window never causes existing windows to resize.

Built from upstream source; see /usr/share/doc/niri/README.build."

build_depends=(
  cargo rustc clang pkgconf
  libudev-dev libgbm-dev libxkbcommon-dev libegl1-mesa-dev libwayland-dev
  libinput-dev libdbus-1-dev libsystemd-dev libseat-dev libpipewire-0.3-dev
  libpango1.0-dev libdisplay-info-dev
)

# libwayland-server is dlopen()ed, so shlibdeps can't see it.
depends=(libwayland-server0)
# Upstream's "strongly recommended" list.
recommends=(xwayland-satellite xdg-desktop-portal-gnome xdg-desktop-portal-gtk gnome-keyring)
suggests=(fuzzel alacritty mako-notifier)

build() {
  ensure_rust
  # Without a .git dir niri can't find its commit; give it the real one.
  export NIRI_BUILD_COMMIT="${commit:0:7}"
  # Default features (dbus, systemd, xdp-gnome-screencast). Never --all-features.
  cargo build --release --locked -j "$jobs"
}

package() {
  # Not stripped on purpose: upstream wants line tables for usable panic backtraces.
  install -Dm755 target/release/niri          "$pkgdir/usr/bin/niri"
  install -Dm755 resources/niri-session       "$pkgdir/usr/bin/niri-session"
  install -Dm644 resources/niri.desktop       "$pkgdir/usr/share/wayland-sessions/niri.desktop"
  install -Dm644 resources/niri-portals.conf  "$pkgdir/usr/share/xdg-desktop-portal/niri-portals.conf"
  install -Dm644 resources/niri.service       "$pkgdir/usr/lib/systemd/user/niri.service"
  install -Dm644 resources/niri-shutdown.target "$pkgdir/usr/lib/systemd/user/niri-shutdown.target"
  install -Dm644 resources/default-config.kdl "$pkgdir/usr/share/niri/default-config.kdl"

  # Shell completions
  local bin=target/release/niri
  install -d "$pkgdir/usr/share/bash-completion/completions" \
             "$pkgdir/usr/share/zsh/vendor-completions" \
             "$pkgdir/usr/share/fish/vendor_completions.d"
  "$bin" completions bash > "$pkgdir/usr/share/bash-completion/completions/niri"
  "$bin" completions zsh  > "$pkgdir/usr/share/zsh/vendor-completions/_niri"
  "$bin" completions fish > "$pkgdir/usr/share/fish/vendor_completions.d/niri.fish"
}

# Runs in a clean container after `apt install ./niri_*.deb`.
smoke_test() {
  niri --version
  niri validate -c /usr/share/niri/default-config.kdl
}
