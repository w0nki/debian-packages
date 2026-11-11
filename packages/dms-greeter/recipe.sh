# shellcheck shell=bash
# dms-greeter — the DMS login screen for greetd (upstream repo: dux-greeter)
#
# Packaged under the same name as the DMS repo's package, so it upgrades the
# one already installed in place instead of removing it first (removal could
# run that package's cleanup scripts and break your login screen).

pkgname=dms-greeter
upstream_git=https://github.com/duxlabs-dev/dux-greeter.git
homepage=https://github.com/duxlabs-dev/dux-greeter

# Same release numbers as dms itself (v2.1.2 and so on).
track=tags
tag_regex='^v[0-9]+\.[0-9]+\.[0-9]+$'
pkgrel=1
arches=(amd64)

section=x11
summary="DMS login screen for greetd"
description="A greetd greeter built on Quickshell, styled to match DankMaterialShell.
It runs inside a compositor (niri by default) as the 'greeter' user.

On a new machine, set up greetd to use it with:  sudo dms-greeter install
Built from upstream source; see /usr/share/doc/dms-greeter/README.build."

build_depends=(golang-go make)

# quickshell comes from trixie-backports.
depends=(
  greetd quickshell
  qml6-module-qtcore qml6-module-qtqml qml6-module-qtquick
  qml6-module-qtquick-controls qml6-module-qtquick-effects
  qml6-module-qtquick-layouts qml6-module-qtquick-templates
  qml6-module-qtquick-window
)
recommends=(niri)

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
  install -Dm755 core/bin/dms-greeter "$pkgdir/usr/bin/dms-greeter"

  # The 'greeter' system user and its cache/home dirs; postinst applies these.
  install -Dm644 assets/systemd/sysusers-dms-greeter.conf "$pkgdir/usr/lib/sysusers.d/dms-greeter.conf"
  install -Dm644 assets/systemd/tmpfiles-dms-greeter.conf "$pkgdir/usr/lib/tmpfiles.d/dms-greeter.conf"

  install -d "$pkgdir/usr/share/doc/dms-greeter/examples"
  cp -r assets/examples/. "$pkgdir/usr/share/doc/dms-greeter/examples/"

  local bin=core/bin/dms-greeter
  install -d "$pkgdir/usr/share/bash-completion/completions" \
             "$pkgdir/usr/share/zsh/vendor-completions" \
             "$pkgdir/usr/share/fish/vendor_completions.d"
  "$bin" completion bash > "$pkgdir/usr/share/bash-completion/completions/dms-greeter" || true
  "$bin" completion zsh  > "$pkgdir/usr/share/zsh/vendor-completions/_dms-greeter" || true
  "$bin" completion fish > "$pkgdir/usr/share/fish/vendor_completions.d/dms-greeter.fish" || true
}

smoke_test() {
  dms-greeter version
  getent passwd greeter          # postinst created the greeter user
  test -d /var/cache/dms-greeter
}
