#!/usr/bin/env bash
# Decide what needs building: for each enabled recipe, find the newest stable
# upstream ref and compare it with what the published repo already has.
#
#   scripts/check-updates.sh [package]      (FORCE=1 rebuilds even if published)
#
# Reads the published Packages indexes from the gh-pages branch (or from
# $PUBLISHED_DIR if set, for local testing). Prints a human summary to stderr;
# writes a GitHub Actions matrix to $GITHUB_OUTPUT when running in CI.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

only="${1:-}"
force="${FORCE:-0}"

# --- what's already published -------------------------------------------
published_index() {  # prints "package version" lines for an arch
  local arch="$1" path="dists/$SUITE/$COMPONENT/binary-$1/Packages"
  if [[ -n "${PUBLISHED_DIR:-}" ]]; then
    cat "$PUBLISHED_DIR/$path" 2>/dev/null || true
  else
    git -C "$REPO_ROOT" show "FETCH_HEAD:$path" 2>/dev/null || true
  fi | awk 'BEGIN { RS = ""; FS = "\n" }
            { p = v = ""
              for (i = 1; i <= NF; i++) {
                if ($i ~ /^Package: /) p = substr($i, 10)
                if ($i ~ /^Version: /) v = substr($i, 10)
              }
              if (p != "") print p, v }'
}
if [[ -z "${PUBLISHED_DIR:-}" ]]; then
  git -C "$REPO_ROOT" fetch --quiet --depth 1 origin gh-pages 2>/dev/null \
    || warn "no gh-pages branch yet; treating everything as unpublished"
fi

# --- compare ------------------------------------------------------------
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
for name in $(list_recipes); do
  [[ -n "$only" && "$name" != "$only" ]] && continue
  (
    load_recipe "$name"
    if [[ "$enabled" != true && -z "$only" ]]; then
      log "$name: disabled, skipping"; exit 0
    fi
    ref="$(latest_ref)" || { warn "$name: couldn't determine upstream ref"; exit 0; }
    [[ -n "$ref" ]] || { warn "$name: no ref matched (check tag_regex)"; exit 0; }

    if [[ "$track" == tags ]]; then
      want="$(version_from_tag "$ref")-$(deb_revision)"
      matches() { [[ "$1" == "$want" ]]; }
    else
      want="*.${ref:0:7}-$(deb_revision)"
      matches() { [[ "$1" == *".${ref:0:7}-$(deb_revision)" ]]; }
    fi

    for arch in "${arches[@]}"; do
      have=""
      while read -r p v; do
        [[ "$p" == "$name" ]] && matches "$v" && have="$v"
      done < <(published_index "$arch")
      if [[ -n "$have" && "$force" != 1 ]]; then
        log "$name/$arch: $have is current"
        continue
      fi
      runner="${RUNNER_FOR_ARCH[$arch]:-}"
      [[ -n "$runner" ]] || { warn "$name: no runner configured for arch $arch"; continue; }
      log "$name/$arch: needs build -> $want (ref $ref)"
      printf '{"pkg":"%s","ref":"%s","arch":"%s","runner":"%s"}\n' "$name" "$ref" "$arch" "$runner"
    done
  )
done > "$tmp"

mapfile -t entries < <(grep -v '^$' "$tmp" || true)

matrix="{\"include\":[$(IFS=,; echo "${entries[*]}")]}"
any=false; ((${#entries[@]})) && any=true

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "matrix=$matrix" >> "$GITHUB_OUTPUT"
  echo "any=$any" >> "$GITHUB_OUTPUT"
fi
echo "$matrix"
