# shellcheck shell=bash
# dms — DankMaterialShell (now "Dux Modular Shell"), a Quickshell desktop shell
# Layout follows upstream's own Debian packaging in distro/debian/dms, except
# that the dms binary is built from source here instead of downloaded prebuilt.

pkgname=dms
upstream_git=https://github.com/duxlabs-dev/dux-shell.git
homepage=https://github.com/duxlabs-dev/dux-shell

# Releases are vX.Y.Z; skips betas and anything else.
track=tags
tag_regex='^v[0-9]+\.[0-9]+\.[0-9]+$'
pkgrel=1
arches=(amd64)

section=x11
summary="DankMaterialShell desktop shell for niri and other Wayland compositors"
description="DMS is a desktop shell built on Quickshell: bar, launcher, notifications,
control center, lock screen and wallpaper-based theming for niri, Hyprland,
sway and other Wayland compositors.

Built from upstream source; see /usr/share/doc/dms/README.build."

build_depends=(golang-go make)

# quickshell comes from trixie-backports (see EXTRA_APT_SOURCES in config.sh).
# matugen and dux-search are built by this repo too.
depends=(
  quickshell accountsservice cava matugen dux-search qt6ct
  qml6-module-qtcore qml6-module-qtmultimedia qml6-module-qtqml
  qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-dialogs
  qml6-module-qtquick-effects qml6-module-qtquick-layouts
  qml6-module-qtquick-templates qml6-module-qtquick-window
)
suggests=(cups-pk-helper)
# Upstream's own packages use these names; don't let both be installed.
conflicts=(dms-git)
replaces=(dms-git)

build() {
  # The shell's shared QML widgets live in a git submodule (dux-qml-common).
  [[ -e quickshell/DCommon/Widgets/DIcon.qml ]] || die "dux-qml-common submodule missing"
  cd core || die "no core dir"
  ensure_go
  make build \
    VERSION="$upstream_version" \
    COMMIT="${commit:0:8}" \
    BUILD_TIME="$(date -u +%Y-%m-%d_%H:%M:%S)"
}

package() {
  install -Dm755 core/bin/dms "$pkgdir/usr/bin/dms"

  # The QML shell itself. -L follows the DCommon symlink into the submodule.
  install -d "$pkgdir/usr/share/quickshell/dms"
  cp -rL quickshell/. "$pkgdir/usr/share/quickshell/dms/"
  rm -rf "$pkgdir/usr/share/quickshell/dms/"{core,distro,tests,.git*}

  install -Dm644 assets/systemd/dms.service "$pkgdir/usr/lib/systemd/user/dms.service"
  install -Dm644 assets/dms-open.desktop "$pkgdir/usr/share/applications/dms-open.desktop"
  install -Dm644 assets/dev.duxlabs.shell.desktop "$pkgdir/usr/share/applications/dev.duxlabs.shell.desktop"
  install -Dm644 assets/dev.duxlabs.shell.notepad.desktop "$pkgdir/usr/share/applications/dev.duxlabs.shell.notepad.desktop"
  install -Dm644 assets/dev.duxlabs.shell.svg "$pkgdir/usr/share/icons/hicolor/scalable/apps/dev.duxlabs.shell.svg"

  local bin=core/bin/dms
  install -d "$pkgdir/usr/share/bash-completion/completions" \
             "$pkgdir/usr/share/zsh/vendor-completions" \
             "$pkgdir/usr/share/fish/vendor_completions.d"
  "$bin" completion bash > "$pkgdir/usr/share/bash-completion/completions/dms" || true
  "$bin" completion zsh  > "$pkgdir/usr/share/zsh/vendor-completions/_dms" || true
  "$bin" completion fish > "$pkgdir/usr/share/fish/vendor_completions.d/dms.fish" || true
}

smoke_test() {
    # The test container runs as root, and dms refuses to start as root,
  # so run it as the unprivileged "nobody" user with a throwaway home dir.
  local home; home="$(mktemp -d)"; chown nobody "$home"
  runuser -u nobody -- env HOME="$home" dms version
  test -f /usr/share/quickshell/dms/shell.qml
  test -f /usr/share/quickshell/dms/DCommon/Widgets/DIcon.qml
  command -v qs || command -v quickshell
}
