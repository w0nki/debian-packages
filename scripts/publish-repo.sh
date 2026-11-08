#!/usr/bin/env bash
# Add .debs to an apt repository tree, prune old versions, regenerate the
# indexes and sign them.
#
#   scripts/publish-repo.sh <site-dir> [incoming-dir]
#
# Needs apt-utils (apt-ftparchive), gnupg and dpkg-dev. Signs with the secret
# key in the current GnuPG keyring (or $SIGNING_KEY_ID if several are present).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

site="$(realpath -m "${1:?usage: publish-repo.sh <site-dir> [incoming-dir]}")"
incoming="${2:+$(realpath "$2")}"
mkdir -p "$site"
cd "$site"

# --- add new packages to the pool ----------------------------------------
pool_dir_for() {  # Debian-style pool path: pool/main/n/niri, pool/main/libf/libfoo
  local p="$1" prefix="${1:0:1}"
  [[ "$p" == lib?* ]] && prefix="${p:0:4}"
  echo "pool/$COMPONENT/$prefix/$p"
}

if [[ -n "$incoming" ]]; then
  shopt -s nullglob globstar
  for deb in "$incoming"/**/*.deb; do
    p="$(dpkg-deb --field "$deb" Package)"
    dest="$(pool_dir_for "$p")"
    mkdir -p "$dest"
    cp -f "$deb" "$dest/"
    log "added $(basename "$deb")"
  done
  shopt -u nullglob globstar
fi
mkdir -p "pool/$COMPONENT"

# --- prune: keep the newest $KEEP_VERSIONS per package+arch --------------
declare -A groups=()
while IFS= read -r -d '' deb; do
  key="$(dpkg-deb --field "$deb" Package Architecture | awk -F': ' '{printf "%s/", $2}')"
  groups["$key"]+="$deb"$'\n'
done < <(find pool -name '*.deb' -print0)

for key in "${!groups[@]}"; do
  mapfile -t debs < <(printf '%s' "${groups[$key]}")
  # Sort newest-first using dpkg's own version comparison.
  sorted=()
  for d in "${debs[@]}"; do
    v="$(dpkg-deb --field "$d" Version)"
    i=0
    while ((i < ${#sorted[@]})); do
      sv="$(dpkg-deb --field "${sorted[i]}" Version)"
      dpkg --compare-versions "$v" gt "$sv" && break
      ((i++)) || true
    done
    sorted=("${sorted[@]:0:i}" "$d" "${sorted[@]:i}")
  done
  for d in "${sorted[@]:KEEP_VERSIONS}"; do
    log "pruning $(basename "$d")"
    rm -f "$d"
  done
done
find pool -type d -empty -delete 2>/dev/null || true
mkdir -p "pool/$COMPONENT"

# --- indexes ------------------------------------------------------------
dist="dists/$SUITE"
rm -rf "$dist"
mapfile -t archs < <(find pool -name '*.deb' -exec dpkg-deb --field {} Architecture \; | grep -vx all | sort -u)
((${#archs[@]})) || archs=(amd64)

for a in "${archs[@]}"; do
  d="$dist/$COMPONENT/binary-$a"
  mkdir -p "$d"
  apt-ftparchive --arch "$a" packages "pool/$COMPONENT" > "$d/Packages"
  gzip -9nk "$d/Packages"
  xz -kf "$d/Packages"
done

apt-ftparchive \
  -o "APT::FTPArchive::Release::Origin=$ORIGIN" \
  -o "APT::FTPArchive::Release::Label=$LABEL" \
  -o "APT::FTPArchive::Release::Suite=$SUITE" \
  -o "APT::FTPArchive::Release::Codename=$SUITE" \
  -o "APT::FTPArchive::Release::Architectures=${archs[*]}" \
  -o "APT::FTPArchive::Release::Components=$COMPONENT" \
  -o "APT::FTPArchive::Release::Description=$DESCRIPTION" \
  release "$dist" > "$dist/Release.tmp"
mv "$dist/Release.tmp" "$dist/Release"

# --- sign ---------------------------------------------------------------
# Prefer the fingerprint of the committed public key, so a wrong secret fails loudly.
if [[ -z "${SIGNING_KEY_ID:-}" && -f "$REPO_ROOT/keys/archive-keyring.gpg" ]]; then
  SIGNING_KEY_ID="$(gpg --show-keys --with-colons "$REPO_ROOT/keys/archive-keyring.gpg" | awk -F: '/^fpr/ {print $10; exit}')"
fi
keyid="${SIGNING_KEY_ID:-$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr/ {print $10; exit}')}"
[[ -n "$keyid" ]] || die "no secret key in the GnuPG keyring to sign with"
gpg_sign() { gpg --batch --yes --pinentry-mode loopback --local-user "$keyid" "$@"; }
gpg_sign --clearsign --digest-algo SHA512 -o "$dist/InRelease" "$dist/Release"
gpg_sign --armor --detach-sign --digest-algo SHA512 -o "$dist/Release.gpg" "$dist/Release"
log "signed with $keyid"

gpg --export "$keyid" > archive-keyring.gpg
gpg --armor --export "$keyid" > archive-keyring.asc

# --- landing page -------------------------------------------------------
touch .nojekyll
{
  cat <<EOF
<!doctype html><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
<title>$LABEL</title>
<style>body{font:15px/1.5 system-ui,sans-serif;max-width:46rem;margin:2rem auto;padding:0 1rem}
pre{background:#f3f3f3;padding:.75rem;overflow-x:auto}td{padding:.15rem .8rem .15rem 0}</style>
<h1>$LABEL</h1>
<p>Apt repository for Debian $SUITE ($COMPONENT). Signing key fingerprint:</p>
<pre>$keyid</pre>
<table><tr><th align=left>Package</th><th align=left>Version</th><th align=left>Arch</th></tr>
EOF
  find pool -name '*.deb' -print0 | sort -z | while IFS= read -r -d '' deb; do
    IFS=$'\t' read -r p v a < <(dpkg-deb --showformat='${Package}\t${Version}\t${Architecture}\n' --show "$deb")
    echo "<tr><td>$p</td><td><a href=\"$deb\">$v</a></td><td>$a</td></tr>"
  done
  echo "</table>"
} > index.html

log "repository updated in $site"
