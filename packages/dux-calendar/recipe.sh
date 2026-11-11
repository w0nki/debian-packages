# shellcheck shell=bash
# dux-calendar (dcal) — calendar app from the DMS project (formerly dankcalendar)

pkgname=dux-calendar
upstream_git=https://github.com/duxlabs-dev/dux-calendar.git
homepage=https://github.com/duxlabs-dev/dux-calendar

# Same release numbers as dms itself.
track=tags
tag_regex='^v[0-9]+\.[0-9]+\.[0-9]+$'
pkgrel=1
arches=(amd64)

section=utils
summary="calendar app for DankMaterialShell (dcal)"
description="A calendar built on Quickshell that matches your DMS theme. It can run in
the background so the DMS bar can show your events.

Start it with your session:  systemctl --user enable --now dcal
Built from upstream source; see /usr/share/doc/dux-calendar/README.build."

build_depends=(golang-go make)

# QML modules it imports (quickshell itself is from trixie-backports).
depends=(
  quickshell
  qml6-module-qtcore qml6-module-qtquick qml6-module-qtquick-controls
  qml6-module-qtquick-effects qml6-module-qtquick-layouts
  qml6-module-qtquick-shapes qml6-module-qtquick-templates
  qml6-module-qtquick-window qml6-module-qt-labs-folderlistmodel
)
recommends=(qml6-module-qt-labs-platform)
# Upstream's old names (the DMS repo shipped it as dankcalendar-git).
provides=(dankcalendar)
conflicts=(dankcalendar dankcalendar-git)
replaces=(dankcalendar dankcalendar-git)

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
  install -Dm755 core/bin/dcal "$pkgdir/usr/bin/dcal"
  install -Dm644 assets/dev.duxlabs.calendar.desktop      "$pkgdir/usr/share/applications/dev.duxlabs.calendar.desktop"
  install -Dm644 assets/dev.duxlabs.calendar.svg          "$pkgdir/usr/share/icons/hicolor/scalable/apps/dev.duxlabs.calendar.svg"
  install -Dm644 assets/dev.duxlabs.calendar.metainfo.xml "$pkgdir/usr/share/metainfo/dev.duxlabs.calendar.metainfo.xml"
  install -Dm644 assets/systemd/dcal.service              "$pkgdir/usr/lib/systemd/user/dcal.service"
  # Optional matugen template for theming; see upstream README to enable it.
  install -Dm644 assets/matugen/dankcalendar.json.template \
    "$pkgdir/usr/share/doc/dux-calendar/matugen/dankcalendar.json.template"

  local bin=core/bin/dcal
  install -d "$pkgdir/usr/share/bash-completion/completions" \
             "$pkgdir/usr/share/zsh/vendor-completions" \
             "$pkgdir/usr/share/fish/vendor_completions.d"
  "$bin" completion bash > "$pkgdir/usr/share/bash-completion/completions/dcal" || true
  "$bin" completion zsh  > "$pkgdir/usr/share/zsh/vendor-completions/_dcal" || true
  "$bin" completion fish > "$pkgdir/usr/share/fish/vendor_completions.d/dcal.fish" || true
}

smoke_test() {
  dcal version
}
