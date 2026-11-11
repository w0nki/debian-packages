# shellcheck shell=bash
# dux-files (dfiles) — file manager from the DMS project

pkgname=dux-files
upstream_git=https://github.com/duxlabs-dev/dux-files.git
homepage=https://github.com/duxlabs-dev/dux-files

# Same release numbers as dms itself.
track=tags
tag_regex='^v[0-9]+\.[0-9]+\.[0-9]+$'
pkgrel=1
arches=(amd64)

section=utils
summary="file manager for DankMaterialShell (dfiles)"
description="A file manager built on Quickshell with tabs, split views, trash and
network shares, using your DMS theme. It can also act as the desktop's file
picker (xdg-desktop-portal) and as the default 'show in folder' handler.

Built from upstream source; see /usr/share/doc/dux-files/README.build."

build_depends=(golang-go make)

# QML modules it imports (quickshell itself is from trixie-backports).
depends=(
  quickshell
  qml6-module-qtcore qml6-module-qtquick qml6-module-qtquick-controls
  qml6-module-qtquick-effects qml6-module-qtquick-layouts
  qml6-module-qtquick-shapes qml6-module-qtquick-templates
  qml6-module-qtquick-window qml6-module-qt-labs-folderlistmodel
)
# PDF previews, and the tools upstream uses for thumbnails.
recommends=(qml6-module-qtquick-pdf ffmpegthumbnailer poppler-utils bubblewrap)

build() {
  # The UI is baked into the binary; it includes the dux-qml-common submodule.
  cd core || die "no core dir"
  ensure_go
  make build \
    VERSION="$upstream_version" \
    COMMIT="${commit:0:8}" \
    BUILD_TIME="$(date -u +%Y-%m-%d_%H:%M:%S)"
}

package() {
  install -Dm755 core/bin/dfiles "$pkgdir/usr/bin/dfiles"
  install -Dm644 assets/dev.duxlabs.files.desktop      "$pkgdir/usr/share/applications/dev.duxlabs.files.desktop"
  install -Dm644 assets/dev.duxlabs.files.svg          "$pkgdir/usr/share/icons/hicolor/scalable/apps/dev.duxlabs.files.svg"
  install -Dm644 assets/dev.duxlabs.files.metainfo.xml "$pkgdir/usr/share/metainfo/dev.duxlabs.files.metainfo.xml"
  # Lets it ask for admin rights (polkit) for actions that need them.
  install -Dm644 assets/dev.duxlabs.files.policy       "$pkgdir/usr/share/polkit-1/actions/dev.duxlabs.files.policy"
  # D-Bus activation: as the "show in file manager" handler, and as a file-picker portal.
  install -Dm644 assets/dbus/dev.duxlabs.files.FileManager1.service \
    "$pkgdir/usr/share/dbus-1/services/dev.duxlabs.files.FileManager1.service"
  install -Dm644 assets/dbus/org.freedesktop.impl.portal.desktop.dfiles.service \
    "$pkgdir/usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.dfiles.service"
  install -Dm644 assets/portal/dfiles.portal "$pkgdir/usr/share/xdg-desktop-portal/portals/dfiles.portal"
  install -Dm644 assets/systemd/dfiles.service "$pkgdir/usr/lib/systemd/user/dfiles.service"

  local bin=core/bin/dfiles
  install -d "$pkgdir/usr/share/bash-completion/completions" \
             "$pkgdir/usr/share/zsh/vendor-completions" \
             "$pkgdir/usr/share/fish/vendor_completions.d"
  "$bin" completion bash > "$pkgdir/usr/share/bash-completion/completions/dfiles" || true
  "$bin" completion zsh  > "$pkgdir/usr/share/zsh/vendor-completions/_dfiles" || true
  "$bin" completion fish > "$pkgdir/usr/share/fish/vendor_completions.d/dfiles.fish" || true
}

smoke_test() {
  dfiles version
}
