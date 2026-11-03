#!/usr/bin/env nix
#!nix shell nixpkgs#curl nixpkgs#jq nixpkgs#nix --command bash
set -euo pipefail
shopt -s inherit_errexit

existing_file="versions.nix"
[ -f "$existing_file" ] || echo "{}" >"$existing_file"

gh_api() {
  local auth=()
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  curl -fsSL "${auth[@]}" "https://api.github.com/$1"
}

# jq -e fails on null/false, so a missing field aborts instead of yielding "null"
jqe() { jq -er "$@"; }

require() {
  [[ -n "$2" && "$2" != "null" ]] || {
    echo "error: could not determine $1" >&2
    exit 1
  }
}

odin_releases=$(gh_api repos/odin-lang/Odin/releases)
ols_releases=$(gh_api repos/DanielGavin/ols/releases)

latest_tag=$(jqe '[.[] | select(.tag_name | startswith("dev-"))][0].tag_name' <<<"$odin_releases")
nightly_rev=$(gh_api repos/odin-lang/Odin/commits/master | jqe '.sha')
ols_latest_tag=$(jqe '[.[] | select(.tag_name | startswith("dev-"))][0].tag_name' <<<"$ols_releases")
# resolve the moving "nightly" tag to a fixed commit so the hash stays valid
ols_nightly_rev=$(gh_api repos/DanielGavin/ols/commits/nightly | jqe '.sha')

require "Odin stable tag" "$latest_tag"
require "Odin nightly rev" "$nightly_rev"
require "ols stable tag" "$ols_latest_tag"
require "ols nightly rev" "$ols_nightly_rev"

prefetch() { # $1 = owner/repo, $2 = rev
  local url="https://github.com/$1/archive/$2.tar.gz" raw
  echo "prefetching $url" >&2
  raw=$(nix-prefetch-url --unpack "$url") || {
    echo "error: failed to fetch $url" >&2
    exit 1
  }
  nix hash convert --hash-algo sha256 --to sri "$raw"
}

old() { nix eval --raw -f "$existing_file" "$1.rev" 2>/dev/null || true; }

entry() { # $1 = attr, $2 = owner/repo, $3 = rev
  if [ "$(old "$1")" = "$3" ]; then
    echo "  $1 = $(nix eval -f "$existing_file" "$1");"
  else
    local hash
    hash=$(prefetch "$2" "$3")
    echo "  $1 = { rev = \"$3\"; sha256 = \"$hash\"; };"
  fi
}

{
  echo "{"
  entry stable odin-lang/Odin "$latest_tag"
  entry nightly odin-lang/Odin "$nightly_rev"
  entry ols-stable DanielGavin/ols "$ols_latest_tag"
  entry ols-nightly DanielGavin/ols "$ols_nightly_rev"
  echo "}"
} >versions.nix.new
mv versions.nix.new versions.nix
