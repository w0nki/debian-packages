#!/usr/bin/env bash
# Build one package from upstream source into a .deb.
#
#   scripts/build-package.sh <package> [ref] [outdir]
#
# ref defaults to the latest stable ref (see latest_ref in lib.sh).
# Intended to run as root inside a clean debian:$SUITE container (CI or
# scripts/local-build.sh). Set SKIP_APT=1 to skip installing build deps.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

name="${1:?usage: build-package.sh <package> [ref] [outdir]}"
upstream_ref="${2:-}"
outdir="$(realpath -m "${3:-$REPO_ROOT/out}")"

load_recipe "$name"
arch="$(dpkg --print-architecture)"
jobs="$(nproc)"
export DEBIAN_FRONTEND=noninteractive

# --- build dependencies ----------------------------------------------------
if [[ "${SKIP_APT:-0}" != 1 ]]; then
  log "installing build dependencies"
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends \
    build-essential dpkg-dev git ca-certificates curl file xz-utils minisign \
    "${build_depends[@]}" >/dev/null
fi

if [[ -z "$upstream_ref" ]]; then
  upstream_ref="$(latest_ref)" || die "could not determine latest ref"
fi
log "building $pkgname at $upstream_ref for $arch"

# --- fetch --------------------------------------------------------------
work="$(mktemp -d "${TMPDIR:-/tmp}/build-$pkgname.XXXXXX")"
srcdir="$work/src"
pkgdir="$work/pkg"
commit=""
mkdir -p "$pkgdir" "$outdir"
fetch
[[ -d "$srcdir" ]] || die "fetch() did not create \$srcdir"

upstream_version="$(upstream_version_for "$upstream_ref" "$srcdir")"
debversion="${upstream_version}-$(deb_revision)"
log "package version $debversion"
export pkgname upstream_ref upstream_version debversion commit srcdir pkgdir jobs arch

# --- build + install into $pkgdir ---------------------------------------
cd "$srcdir"
log "build()"
build
cd "$srcdir"
log "package()"
package

# --- docs ---------------------------------------------------------------
docdir="$pkgdir/usr/share/doc/$pkgname"
mkdir -p "$docdir"
if [[ -n "$license_file" && -f "$srcdir/$license_file" ]]; then
  install -m644 "$srcdir/$license_file" "$docdir/copyright"
else
  warn "license file '$license_file' not found; package will lack a copyright file"
fi
cat > "$docdir/README.build" <<EOF
Built from $upstream_git
ref:    $upstream_ref
commit: ${commit:-unknown}
by:     ${GITHUB_SERVER_URL:-local}/${GITHUB_REPOSITORY:-}${GITHUB_RUN_ID:+/actions/runs/$GITHUB_RUN_ID}
EOF

# --- control file -------------------------------------------------------
join_deps() { local IFS=,; echo "$*" | sed -E 's/, */, /g'; }

# Shared-library dependencies, worked out from the ELF files we ship.
mapfile -t elfs < <(find "$pkgdir" -type f -exec file -N --mime-type {} + \
  | awk -F': ' '$2 ~ /application\/x-(pie-)?(executable|sharedlib)/ {print $1}')
shlibs=""
if ((${#elfs[@]})); then
  shl="$work/shlibdeps"
  mkdir -p "$shl/debian"
  printf 'Source: %s\n\nPackage: %s\nArchitecture: any\n' "$pkgname" "$pkgname" > "$shl/debian/control"
  shlibs="$(cd "$shl" && dpkg-shlibdeps -O --ignore-missing-info "${elfs[@]/#/-e}" 2>/dev/null \
            | sed -n 's/^shlibs:Depends=//p')"
fi
all_depends="$(join_deps ${shlibs:+"$shlibs"} "${depends[@]}")"

installed_size="$(du -sk --exclude=DEBIAN "$pkgdir" | cut -f1)"
mkdir -p "$pkgdir/DEBIAN"
{
  echo "Package: $pkgname"
  echo "Version: $debversion"
  echo "Architecture: $arch"
  echo "Maintainer: $MAINTAINER"
  echo "Installed-Size: $installed_size"
  [[ -n "$all_depends" ]]   && echo "Depends: $all_depends"
  ((${#recommends[@]}))     && echo "Recommends: $(join_deps "${recommends[@]}")"
  ((${#suggests[@]}))       && echo "Suggests: $(join_deps "${suggests[@]}")"
  ((${#provides[@]}))       && echo "Provides: $(join_deps "${provides[@]}")"
  ((${#conflicts[@]}))      && echo "Conflicts: $(join_deps "${conflicts[@]}")"
  ((${#replaces[@]}))       && echo "Replaces: $(join_deps "${replaces[@]}")"
  echo "Section: $section"
  echo "Priority: $priority"
  [[ -n "$homepage" ]] && echo "Homepage: $homepage"
  echo "Description: $summary"
  if [[ -n "$description" ]]; then
    # Continuation lines start with a space; blank lines become " ."
    sed -e 's/^[[:space:]]*$/./' -e 's/^/ /' <<<"$description"
  fi
} > "$pkgdir/DEBIAN/control"

# Anything under /etc is a conffile (dpkg won't clobber local edits).
if [[ -d "$pkgdir/etc" ]]; then
  (cd "$pkgdir" && find etc -type f -printf '/%p\n') > "$pkgdir/DEBIAN/conffiles"
fi
# md5sums for debsums / dpkg --verify
(cd "$pkgdir" && find . -path ./DEBIAN -prune -o -type f -printf '%P\0' \
  | xargs -0r md5sum) > "$pkgdir/DEBIAN/md5sums"

# Optional maintainer scripts shipped next to the recipe.
for s in postinst prerm postrm preinst; do
  [[ -f "$REPO_ROOT/packages/$name/$s" ]] && install -m755 "$REPO_ROOT/packages/$name/$s" "$pkgdir/DEBIAN/$s"
done

# --- assemble -----------------------------------------------------------
deb="$outdir/${pkgname}_${debversion}_${arch}.deb"
dpkg-deb --root-owner-group -Zxz --build "$pkgdir" "$deb" >/dev/null
log "built $deb"
dpkg-deb --field "$deb" Package Version Architecture Depends Installed-Size >&2

rm -rf "$work"
# Last line of stdout is the path, for scripts that want it.
echo "$deb"
