# Shared helpers. Source this; don't run it.
# shellcheck shell=bash

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config.sh
source "$REPO_ROOT/config.sh"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m==> WARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m==> ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Recipes
# ---------------------------------------------------------------------------

# Defaults a recipe may override.
recipe_defaults() {
  enabled=true
  track=tags                       # tags | branch
  tag_regex='^v?[0-9]+(\.[0-9]+)+$' # stable release tags only (no rc/beta/alpha)
  branch=main
  require_green_ci=false           # branch mode: only take commits whose GitHub checks passed
  pkgrel=1
  arches=(amd64)
  rust_toolchain=auto              # auto: Debian's rustc if new enough, else rustup | stable: always rustup
  section=misc
  priority=optional
  homepage=""
  summary=""
  description=""
  license_file=LICENSE
  build_depends=()
  depends=()
  recommends=()
  suggests=()
  provides=()
  conflicts=()
  replaces=()
  # Turn a tag into an upstream version string: v26.04 -> 26.04
  version_from_tag() { local t="$1"; echo "${t#v}"; }
  # Default fetch: shallow clone of the tag, or a blobless clone at the commit.
  fetch() { default_fetch; }
  smoke_test() { :; }
}

list_recipes() {
  local d
  for d in "$REPO_ROOT"/packages/*/; do
    [[ -f "$d/recipe.sh" ]] && basename "$d"
  done
}

load_recipe() {
  local name="$1" file="$REPO_ROOT/packages/$1/recipe.sh"
  [[ -f "$file" ]] || die "no recipe at packages/$name/recipe.sh"
  recipe_defaults
  # shellcheck source=/dev/null
  source "$file"
  [[ "${pkgname:-}" == "$name" ]] || die "packages/$name/recipe.sh must set pkgname=$name"
  [[ -n "${upstream_git:-}" ]] || die "$name: upstream_git is required"
  [[ -n "$summary" ]] || die "$name: summary is required"
}

# ---------------------------------------------------------------------------
# Upstream discovery
# ---------------------------------------------------------------------------

# Print the ref to build: the newest stable tag, or a commit sha in branch mode.
latest_ref() {
  case "$track" in
    tags)
      git ls-remote --tags --refs "$upstream_git" \
        | awk '{ sub("^refs/tags/", "", $2); print $2 }' \
        | grep -E -- "$tag_regex" \
        | sort -V | tail -n1
      ;;
    branch)
      if [[ "$require_green_ci" == true ]]; then
        latest_green_commit
      else
        git ls-remote "$upstream_git" "refs/heads/$branch" | cut -f1
      fi
      ;;
    *) die "$pkgname: unknown track '$track'" ;;
  esac
}

# Newest commit on $branch (of the last 20) whose GitHub check runs all passed.
latest_green_commit() {
  local slug sha verdict
  slug="$(sed -E 's#^https://github.com/##; s#\.git$##' <<<"$upstream_git")"
  [[ "$slug" == */* && "$upstream_git" == https://github.com/* ]] \
    || die "$pkgname: require_green_ci only works for github.com upstreams"
  command -v gh >/dev/null || die "require_green_ci needs the gh CLI"
  for sha in $(gh api "repos/$slug/commits?sha=$branch&per_page=20" --jq '.[].sha'); do
    # "green" = at least one check run, all completed, none failed/cancelled/timed out.
    verdict="$(gh api "repos/$slug/commits/$sha/check-runs?per_page=100" --jq '
      .check_runs as $r
      | if ($r | length) == 0 then "none"
        elif any($r[]; .status != "completed") then "pending"
        elif all($r[]; .conclusion == "success" or .conclusion == "skipped" or .conclusion == "neutral") then "green"
        else "red" end')"
    if [[ "$verdict" == green ]]; then echo "$sha"; return 0; fi
  done
  warn "$pkgname: no green commit in the last 20 on $branch"
  return 1
}

# Upstream version for a ref. In branch mode this needs the source checkout.
upstream_version_for() {
  local ref="$1" src="${2:-}"
  if [[ "$track" == tags ]]; then
    version_from_tag "$ref"
    return
  fi
  [[ -n "$src" ]] || die "branch mode needs the source tree to compute a version"
  local base date sha
  base="$(git -C "$src" tag --merged HEAD | grep -E -- "$tag_regex" | sort -V | tail -n1 || true)"
  base="${base:+$(version_from_tag "$base")}"
  date="$(TZ=UTC git -C "$src" log -1 --format=%cd --date=format-local:%Y%m%d%H%M)"
  sha="$(git -C "$src" rev-parse --short=7 HEAD)"
  # 26.04+git202611071230.abc1234 sorts above 26.04 and below 26.05
  echo "${base:-0}+git${date}.${sha}"
}

deb_revision() { echo "0${VENDOR_TAG}${pkgrel}"; }

# ---------------------------------------------------------------------------
# Fetching source
# ---------------------------------------------------------------------------

# Uses $upstream_ref and $srcdir.
default_fetch() {
  if [[ "$track" == tags ]]; then
    git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$upstream_ref" "$upstream_git" "$srcdir"
  else
    # Blobless clone keeps history (for `git describe`-style versions) without the bulk.
    git clone --quiet --filter=blob:none --no-checkout "$upstream_git" "$srcdir"
    git -C "$srcdir" checkout --quiet "$upstream_ref"
  fi
  git -C "$srcdir" submodule update --init --recursive --depth 1 --quiet 2>/dev/null || true
  commit="$(git -C "$srcdir" rev-parse HEAD)"
}

# Download a file and check it against a minisign signature.
#   fetch_minisigned URL PUBKEY OUTFILE
fetch_minisigned() {
  local url="$1" key="$2" out="$3"
  curl -fsSL --retry 3 -o "$out" "$url"
  curl -fsSL --retry 3 -o "$out.minisig" "$url.minisig"
  minisign -V -q -P "$key" -m "$out" -x "$out.minisig" \
    || die "minisign verification FAILED for $url"
  log "verified signature: $(basename "$out")"
}

# ---------------------------------------------------------------------------
# Toolchains
# ---------------------------------------------------------------------------

# Use Debian's rustc if it satisfies the crate's rust-version (MSRV); otherwise
# install the stable toolchain with rustup. Call from a recipe's build().
ensure_rust() {
  local need have
  need="$(grep -m1 -E '^rust-version *=' Cargo.toml | sed -E 's/.*"(.*)".*/\1/' || true)"
  have="$(rustc --version 2>/dev/null | awk '{print $2}' || true)"
  if [[ "${rust_toolchain:-auto}" != stable && -n "$have" ]] \
     && { [[ -z "$need" ]] || dpkg --compare-versions "$have" ge "$need"; }; then
    log "using rustc $have (crate needs ${need:-any})"
    return
  fi
  log "rustc ${have:-missing} not suitable (need ${need:-latest stable}); installing stable via rustup"
  if ! command -v rustup >/dev/null; then
    curl -fsSL --proto '=https' --tlsv1.2 https://sh.rustup.rs \
      | sh -s -- -y --profile minimal --default-toolchain stable >&2
    # shellcheck source=/dev/null
    source "$HOME/.cargo/env"
  fi
  export RUSTUP_TOOLCHAIN=stable
  log "using $(rustc --version)"
}

# Go: Debian's go reads the module's `go` line and, with GOTOOLCHAIN=auto,
# fetches that exact toolchain from proxy.golang.org (checked against
# sum.golang.org). Call from the directory holding go.mod.
ensure_go() {
  export GOTOOLCHAIN=auto
  log "using $(go version) (go.mod wants $(awk '/^go /{print $2; exit}' go.mod 2>/dev/null))"
}

# Extra apt sources from config.sh (e.g. backports), for build and test containers.
setup_extra_apt_sources() {
  ((${#EXTRA_APT_SOURCES[@]})) || return 0
  printf '%s\n' "${EXTRA_APT_SOURCES[@]}" > /etc/apt/sources.list.d/extra.list
}

# Download the exact Zig release a project asks for and verify it.
#   ensure_zig 0.15.2
ZIG_PUBKEY="RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U"
ensure_zig() {
  local ver="$1" zarch dir
  case "$(dpkg --print-architecture)" in
    amd64) zarch=x86_64 ;; arm64) zarch=aarch64 ;; *) die "no zig mapping for this arch" ;;
  esac
  dir="/opt/zig-$ver"
  if [[ ! -x "$dir/zig" ]]; then
    local tb="zig-${zarch}-linux-${ver}.tar.xz"
    fetch_minisigned "https://ziglang.org/download/$ver/$tb" "$ZIG_PUBKEY" "/tmp/$tb"
    mkdir -p "$dir"
    tar -xJf "/tmp/$tb" -C "$dir" --strip-components=1
  fi
  export PATH="$dir:$PATH"
  log "using zig $(zig version)"
}
