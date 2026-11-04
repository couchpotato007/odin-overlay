#!/usr/bin/env nix
#!nix shell nixpkgs#bash nixpkgs#curl nixpkgs#jq nixpkgs#git nixpkgs#nix --command bash
# Regenerates sources.json:
#   - every Odin release tag (dev-YYYY-MM[x]) that can be built with an LLVM
#     version still packaged in nixpkgs
#   - Odin nightly (current master)
#   - ols stable (latest dev-* tag) and ols nightly (current master)
# Entries whose rev did not change are reused, so only new versions are fetched.
set -euo pipefail
shopt -s inherit_errexit

cd "$(dirname "$0")"

sources_file="sources.json"
# First Odin release that supports LLVM 18, the oldest LLVM left in nixpkgs.
# Older tags need LLVM <= 17 and can no longer be built.
MIN_TAG="${MIN_TAG:-dev-2024-05}"

[ -f "$sources_file" ] || echo '{"odin": {}, "ols": {}}' >"$sources_file"
old_sources=$(cat "$sources_file")

gh_api() {
  local auth=()
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  curl -fsSL --retry 3 "${auth[@]}" "https://api.github.com/$1"
}

die() {
  echo "error: $*" >&2
  exit 1
}

# $1 = owner/repo, $2 = rev  ->  SRI hash compatible with fetchFromGitHub
prefetch() {
  local url="https://github.com/$1/archive/$2.tar.gz" raw
  echo "prefetching $url" >&2
  raw=$(nix-prefetch-url --unpack "$url" 2>/dev/null) || die "failed to fetch $url"
  nix hash convert --hash-algo sha256 --to sri "$raw"
}

# $1 = rev  ->  JSON array of LLVM majors supported by build_odin.sh, preferred first
llvm_versions() {
  local script supported suggested max
  script=$(curl -fsSL --retry 3 "https://raw.githubusercontent.com/odin-lang/Odin/$1/build_odin.sh") ||
    die "failed to fetch build_odin.sh for $1"

  supported=$(sed -nE 's/^SUPPORTED_LLVM_VERSIONS="([0-9 ]+)".*/\1/p' <<<"$script")
  if [ -n "$supported" ]; then
    suggested=$(sed -nE 's/^SUGGESTED_LLVM_VERSION="?([0-9]+)"?.*/\1/p' <<<"$script")
    jq -cn --arg s "$supported" --arg p "${suggested:-}" '
      ($s | split(" ") | map(select(. != "") | tonumber) | sort | reverse) as $all
      | ([$p | select(. != "") | tonumber] | map(select(. as $x | $all | index($x)))) + $all
      | reduce .[] as $x ([]; if index($x) then . else . + [$x] end)'
  else
    # older scripts: `[ $LLVM_VERSION_MAJOR -gt N ]` marks the newest supported version
    max=$(grep -oE 'LLVM_VERSION_MAJOR -gt [0-9]+' <<<"$script" | grep -oE '[0-9]+$' | sort -n | tail -1 || true)
    [ -n "$max" ] || die "could not determine supported LLVM versions for $1"
    jq -cn --argjson m "$max" '[range($m; 16; -1)]'
  fi
}

# $1 = section (odin|ols), $2 = name  ->  existing entry or null
old_entry() { jq -c --arg s "$1" --arg n "$2" '.[$s][$n] // null' <<<"$old_sources"; }

# $1 = section, $2 = name, $3 = owner/repo, $4 = rev, $5 = version, $6 = with llvm info (true/false)
entry() {
  local old llvm hash
  old=$(old_entry "$1" "$2")
  if [ "$old" != null ] && [ "$(jq -r .rev <<<"$old")" = "$4" ]; then
    jq -c --arg v "$5" '.version = $v' <<<"$old"
    return
  fi
  llvm=null
  [ "$6" = true ] && llvm=$(llvm_versions "$4")
  hash=$(prefetch "$3" "$4")
  jq -cn --arg v "$5" --arg r "$4" --arg h "$hash" --argjson l "$llvm" \
    '{version: $v, rev: $r, hash: $h} + (if $l == null then {} else {llvm: $l} end)'
}

ls_remote() { git ls-remote "https://github.com/$1" "${@:2}"; }

# --- Odin --------------------------------------------------------------------

mapfile -t odin_tags < <(
  ls_remote odin-lang/Odin 'refs/tags/dev-*' |
    sed -nE 's#.*refs/tags/(dev-[0-9]{4}-[0-9]{2}[a-z]?)$#\1#p' |
    awk -v min="$MIN_TAG" '$0 >= min' | sort -u
)
[ "${#odin_tags[@]}" -gt 0 ] || die "no Odin release tags found"

nightly_rev=$(ls_remote odin-lang/Odin refs/heads/master | cut -f1)
[ -n "$nightly_rev" ] || die "could not resolve Odin master"
nightly_date=$(gh_api "repos/odin-lang/Odin/commits/$nightly_rev" | jq -er '.commit.committer.date[:10]')

odin_json='{}'
for tag in "${odin_tags[@]}"; do
  e=$(entry odin "$tag" odin-lang/Odin "$tag" "$tag" true)
  odin_json=$(jq -c --arg n "$tag" --argjson e "$e" '.[$n] = $e' <<<"$odin_json")
done
e=$(entry odin nightly odin-lang/Odin "$nightly_rev" "0-unstable-$nightly_date" true)
odin_json=$(jq -c --argjson e "$e" '.nightly = $e' <<<"$odin_json")

# --- ols ---------------------------------------------------------------------

ols_tag=$(
  ls_remote DanielGavin/ols 'refs/tags/dev-*' |
    sed -nE 's#.*refs/tags/(dev-[0-9]{4}-[0-9]{2}[a-z]?)$#\1#p' | sort | tail -1
)
[ -n "$ols_tag" ] || die "could not determine latest ols tag"
# ols nightly tracks master (its moving "nightly" tag can lag behind Odin
# master for weeks, which breaks building it against Odin nightly)
ols_nightly_rev=$(ls_remote DanielGavin/ols refs/heads/master | cut -f1)
[ -n "$ols_nightly_rev" ] || die "could not resolve ols master"
ols_nightly_date=$(gh_api "repos/DanielGavin/ols/commits/$ols_nightly_rev" | jq -er '.commit.committer.date[:10]')

ols_json=$(jq -cn \
  --argjson s "$(entry ols stable DanielGavin/ols "$ols_tag" "$ols_tag" false)" \
  --argjson n "$(entry ols nightly DanielGavin/ols "$ols_nightly_rev" "0-unstable-$ols_nightly_date" false)" \
  '{stable: $s, nightly: $n}')

jq -n --argjson odin "$odin_json" --argjson ols "$ols_json" '{odin: $odin, ols: $ols}' >"$sources_file.new"
mv "$sources_file.new" "$sources_file"
echo "updated $sources_file" >&2
