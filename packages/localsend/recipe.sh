# shellcheck shell=bash
# localsend — share files with nearby devices over the local network (an open
# AirDrop alternative). A Flutter app with a Rust core.

pkgname=localsend
upstream_git=https://github.com/localsend/localsend.git
homepage=https://localsend.org

track=tags
tag_regex='^v[0-9]+\.[0-9]+\.[0-9]+$'
pkgrel=1
arches=(amd64)

section=net
summary="share files to nearby devices over the local network"
description="LocalSend sends files and messages between devices on the same network,
without the internet or an account: phones, tablets and computers on any OS.
It uses port 53317 (TCP and UDP); open it if a firewall is on.

Built from upstream source; see /usr/share/doc/localsend/README.build."

# What upstream's own release build installs, plus what Flutter needs to run.
build_depends=(
  clang cmake ninja-build pkgconf unzip xz-utils
  libgtk-3-dev libayatana-appindicator3-dev
)
# Tray icon libraries are loaded at runtime, so dpkg-shlibdeps can't see them
# (same list as upstream's own .deb).
depends=(libayatana-appindicator3-1 gir1.2-ayatanaappindicator3-0.1 xdg-user-dirs)

# The Rust part is built by cargokit, which needs rustup and uses the exact
# toolchain pinned in the repo's rust-toolchain.toml.
rust_toolchain=stable

build() {
  # Rust: install rustup, then let rust-toolchain.toml pick the version.
  ensure_rust
  unset RUSTUP_TOOLCHAIN

  # Flutter: the exact SDK version upstream pins in .fvmrc, from Flutter's git repo.
  local flutter_ver
  flutter_ver="$(sed -nE 's/.*"flutter": *"([^"]+)".*/\1/p' .fvmrc)"
  [[ -n "$flutter_ver" ]] || die "couldn't read the Flutter version from .fvmrc"
  if [[ ! -x /opt/flutter/bin/flutter ]]; then
    git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$flutter_ver" \
      https://github.com/flutter/flutter.git /opt/flutter
  fi
  git config --global --add safe.directory /opt/flutter
  export PATH="/opt/flutter/bin:$PATH"
  flutter config --no-analytics >/dev/null
  log "using $(flutter --version | head -n1)"

  cd app || die "no app dir"
  # Build the Rust library from source, never cargokit's prebuilt download.
  printf 'use_precompiled_binaries: false\nverbose_logging: true\n' > cargokit_options.yaml
  flutter pub get
  flutter build linux --release
}

package() {
  local bundle=app/build/linux/x64/release/bundle
  [[ -x "$bundle/localsend_app" ]] || die "Flutter build output not found"

  # The app expects its lib/ and data/ folders next to the binary.
  install -d "$pkgdir/usr/lib/localsend" "$pkgdir/usr/bin"
  cp -r "$bundle/." "$pkgdir/usr/lib/localsend/"
  ln -s ../lib/localsend/localsend_app "$pkgdir/usr/bin/localsend"

  # Named after the app's ID so docks and window rules match the running window.
  local id=org.localsend.localsend_app
  for s in 128 256 512; do
    install -Dm644 "app/assets/img/logo-$s.png" "$pkgdir/usr/share/icons/hicolor/${s}x${s}/apps/$id.png"
  done
  install -d "$pkgdir/usr/share/applications"
  cat > "$pkgdir/usr/share/applications/$id.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=LocalSend
GenericName=File sharing
Comment=Share files to nearby devices
Exec=localsend
Icon=$id
Categories=GTK;Network;FileTransfer;Utility;
Keywords=Sharing;LAN;Files;
StartupNotify=true
StartupWMClass=localsend_app
DESKTOP
}

# It's a GUI app and the test container has no display, so check instead that
# every library the binary and its bundled libraries need is installed.
smoke_test() {
  local f missing
  test -x /usr/lib/localsend/localsend_app
  test -L /usr/bin/localsend
  for f in /usr/lib/localsend/localsend_app /usr/lib/localsend/lib/*.so; do
    missing="$(LD_LIBRARY_PATH=/usr/lib/localsend/lib ldd "$f" | grep 'not found' || true)"
    [[ -z "$missing" ]] || die "$f is missing libraries: $missing"
  done
  echo "all libraries found"
}
