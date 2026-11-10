# shellcheck shell=bash
# sunshine — self-hosted game stream host for Moonlight
#
# Uses upstream's own build script (scripts/linux_build.sh), the same one their
# Debian trixie packages are built with, so dependency lists, the CUDA version
# and CMake options stay in step with upstream. We just install the result
# into a .deb with this repo's tooling instead of CPack.

pkgname=sunshine
upstream_git=https://github.com/LizardByte/Sunshine.git
homepage=https://app.lizardbyte.dev/Sunshine

# Sunshine publishes frequent pre-releases with the same tag format as stable
# releases (vYYYY.MDD.HHMMSS), so the tag name can't tell them apart. Ask
# GitHub which release is marked "latest" instead; that skips pre-releases.
track=tags
tag_regex='^v[0-9]+\.[0-9]+\.[0-9]+$'
latest_ref() {
  command -v gh >/dev/null || die "sunshine: needs the gh CLI to find the latest stable release"
  gh api repos/LizardByte/Sunshine/releases/latest --jq .tag_name
}

pkgrel=1
arches=(amd64)

section=video
summary="self-hosted game stream host for Moonlight"
description="Sunshine streams games and the desktop from this machine to Moonlight
clients, with hardware encoding on NVIDIA (NVENC), AMD and Intel (VA-API).

After installing, enable it for your user:
  systemctl --user enable --now app-dev.lizardbyte.app.Sunshine.service
then open https://localhost:47990 to set it up.

Built from upstream source; see /usr/share/doc/sunshine/README.build."

# Upstream's script installs the real build dependencies itself, including
# the CUDA toolkit for NVENC, which is a multi-GB download.
build_depends=()
large_build=true

# setcap is used by postinst to grant KMS screen capture.
depends=(libcap2-bin)

fetch() {
  git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$upstream_ref" \
    --recurse-submodules --shallow-submodules "$upstream_git" "$srcdir"
  commit="$(git -C "$srcdir" rev-parse HEAD)"
}

build() {
  # Version info for Sunshine's CMake (otherwise it tries to work it out from git).
  export BRANCH=master BUILD_VERSION="$upstream_ref" COMMIT="$commit"

  local opts=(
    --sudo-off
    --cuda-patches   # upstream uses this for its own trixie build (glibc 2.41 vs CUDA headers)
    --num-processors="$jobs"
    --publisher-name="${GITHUB_REPOSITORY:-local build}"
    --publisher-website="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}"
    --publisher-issue-url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/issues"
  )
  # For a machine without an NVIDIA GPU you can skip the large CUDA download:
  #   SUNSHINE_CUDA=0 scripts/local-build.sh sunshine
  [[ "${SUNSHINE_CUDA:-1}" == 1 ]] || opts+=(--skip-cuda)

  ./scripts/linux_build.sh --step=deps "${opts[@]}"
  ./scripts/linux_build.sh --step=cmake "${opts[@]}"
  # We don't ship the tests or docs, so don't spend time building them.
  cmake -B build -DBUILD_TESTS=OFF -DBUILD_DOCS=OFF >/dev/null
  ./scripts/linux_build.sh --step=validation "${opts[@]}"
  ./scripts/linux_build.sh --step=build "${opts[@]}"
}

package() {
  DESTDIR="$pkgdir" cmake --install build
  # The CUDA toolkit is several GB; free the space before the .deb is assembled.
  rm -rf build/cuda
}

smoke_test() {
  sunshine --version
  test -f /usr/lib/udev/rules.d/60-sunshine.rules
  test -f /usr/lib/systemd/user/app-dev.lizardbyte.app.Sunshine.service
  # postinst grants the capabilities KMS capture needs. Some containers
  # don't allow setting them, so only warn here.
  getcap /usr/bin/sunshine | grep -q cap_sys_admin \
    || echo "warning: capabilities not set (normal in some containers)" >&2
}
