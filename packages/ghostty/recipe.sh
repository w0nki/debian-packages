# shellcheck shell=bash
# ghostty — GPU-accelerated terminal emulator (GTK frontend)
#
# Disabled until you've done one manual run: I couldn't test-build this one
# (Zig downloads were blocked where the scaffold was written). Set enabled=true,
# then run the workflow by hand with package=ghostty and watch the log.
enabled=false

pkgname=ghostty
upstream_git=https://github.com/ghostty-org/ghostty.git
homepage=https://ghostty.org

# Releases are vX.Y.Z. The repo also has tags like "tip" and "vt-1.0.0" that we skip.
track=tags
tag_regex='^v[0-9]+\.[0-9]+\.[0-9]+$'
pkgrel=1
arches=(amd64)

section=x11
summary="fast, native, feature-rich terminal emulator"
description="Ghostty is a terminal emulator that uses platform-native UI and
GPU acceleration. This build uses the GTK frontend.

Built from the signed upstream release tarball; see /usr/share/doc/ghostty/README.build."
license_file=LICENSE

build_depends=(
  pkgconf gettext libxml2-utils
  libgtk-4-dev libgtk4-layer-shell-dev libadwaita-1-dev
)
# Ghostty's build docs say Debian testing/unstable also needs gcc-multilib (amd64 only).
[[ "$(dpkg --print-architecture 2>/dev/null)" == amd64 ]] && build_depends+=(gcc-multilib)

# From PACKAGING.md: release tarballs are signed with this minisign key.
GHOSTTY_PUBKEY="RWQlAjJC23149WL2sEpT/l0QKy7hMIFhYdQOFy0Z7z7PbneUgvlsnYcV"

# Use the signed release tarball, not a git checkout: upstream says tarballs
# contain pre-generated files and need fewer build deps.
fetch() {
  local v; v="$(version_from_tag "$upstream_ref")"
  fetch_minisigned "https://release.files.ghostty.org/$v/ghostty-$v.tar.gz" \
    "$GHOSTTY_PUBKEY" "$work/ghostty.tar.gz"
  mkdir -p "$srcdir"
  tar -xzf "$work/ghostty.tar.gz" -C "$srcdir" --strip-components=1
  commit="$(git ls-remote "$upstream_git" "refs/tags/$upstream_ref^{}" "refs/tags/$upstream_ref" | head -n1 | cut -f1)"
}

build() {
  # Each Ghostty release needs one specific Zig; read it from the source.
  local zigver
  zigver="$(sed -nE 's/.*minimum_zig_version *= *"([^"]+)".*/\1/p' build.zig.zon)"
  [[ -n "$zigver" ]] || die "couldn't find minimum_zig_version in build.zig.zon"
  ensure_zig "$zigver"
}

package() {
  # zig build compiles and installs in one step.
  DESTDIR="$pkgdir" zig build \
    --prefix /usr \
    -Doptimize=ReleaseFast \
    -Dcpu=baseline
}

smoke_test() {
  ghostty +version
}
