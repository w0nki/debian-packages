# shellcheck shell=bash
# Repo-wide settings. Sourced by every script.

# Debian release the packages are built for (the build container is debian:$SUITE).
SUITE="trixie"
COMPONENT="main"

# Shown in the Release file. ORIGIN is what apt pinning and unattended-upgrades match on.
ORIGIN="selfbuilt"
LABEL="Self-built packages"
DESCRIPTION="Packages built from upstream source by GitHub Actions"

# Goes in each package's Maintainer field. Change to an address you want public.
MAINTAINER="Package Builder <apt@invalid>"

# Debian revision is "<upstream>-0<VENDOR_TAG><pkgrel>", e.g. niri 26.04-0local1.
# The leading 0 means an official Debian package of the same upstream version
# (26.04-1) sorts higher than yours, so apt would prefer Debian's if it ever ships one.
VENDOR_TAG="local"

# How many versions of each package/arch to keep in the repo (lets you downgrade one step).
KEEP_VERSIONS=2

# GitHub runner label for each architecture.
declare -A RUNNER_FOR_ARCH=(
  [amd64]="ubuntu-24.04"
  [arm64]="ubuntu-24.04-arm"
)
