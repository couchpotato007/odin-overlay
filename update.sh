#!/usr/bin/env nix
#!nix shell nixpkgs#curl nixpkgs#jq nixpkgs#nix --command bash
set -euo pipefail

existing_file="versions.nix"
[ -f "$existing_file" ] || echo "{}" >"$existing_file"

latest_tag=$(curl -s https://api.github.com/repos/odin-lang/Odin/releases | jq -r '[.[] | select(.name | startswith("dev-"))][0].name')
nightly_rev=$(curl -s https://api.github.com/repos/odin-lang/Odin/commits/master | jq -r '.sha')

ols_latest_tag=$(curl -s https://api.github.com/repos/DanielGavin/ols/releases | jq -r '[.[] | select(.name | startswith("dev-"))][0].name')
ols_nightly_tag=$(curl -s https://api.github.com/repos/DanielGavin/ols/releases | jq -r '[.[] | select(.name | startswith("nightly"))][0].name')

prefetch() {
    local raw
    raw=$(nix-prefetch-url --unpack "https://github.com/odin-lang/Odin/archive/$1.tar.gz" 2>/dev/null)
    nix hash convert --hash-algo sha256 --to sri "$raw"
}

prefetch-ols() {
    local raw
    raw=$(nix-prefetch-url --unpack "https://github.com/DanielGavin/ols/archive/$1.tar.gz" 2>/dev/null)
    nix hash convert --hash-algo sha256 --to sri "$raw"
}

old_stable_rev=$(nix eval --raw -f "$existing_file" 'stable.rev' 2>/dev/null || echo "")
old_nightly_rev=$(nix eval --raw -f "$existing_file" 'nightly.rev' 2>/dev/null || echo "")

ols_old_stable_rev=$(nix eval --raw -f "$existing_file" 'ols-stable.rev' 2>/dev/null || echo "")
ols_old_nightly_rev=$(nix eval --raw -f "$existing_file" 'ols-nightly.rev' 2>/dev/null || echo "")

{
    echo "{"

    if [ "$old_stable_rev" = "$latest_tag" ]; then
        echo "  stable = $(nix eval -f "$existing_file" "stable");"
    else
        hash=$(prefetch "$latest_tag")
        echo "  stable = { rev = \"$latest_tag\"; sha256 = \"$hash\"; };"
    fi

    if [ "$old_nightly_rev" = "$nightly_rev" ]; then
        echo "  nightly = $(nix eval -f "$existing_file" "nightly");"
    else
        hash=$(prefetch "$nightly_rev")
        echo "  nightly = { rev = \"$nightly_rev\"; sha256 = \"$hash\"; };"
    fi

    if [ "$ols_old_stable_rev" = "$ols_latest_tag" ]; then
        echo "  ols-stable = $(nix eval -f "$existing_file" "ols-stable");"
    else
        hash=$(prefetch-ols "$ols_latest_tag")
        echo "  ols-stable = { rev = \"$ols_latest_tag\"; sha256 = \"$hash\"; };"
    fi

    if [ "$ols_old_nightly_rev" = "$ols_nightly_tag" ]; then
        echo "  ols-nightly = $(nix eval -f "$existing_file" "ols-nightly");"
    else
        hash=$(prefetch-ols "$ols_nightly_tag")
        echo "  ols-nightly = { rev = \"$ols_nightly_tag\"; sha256 = \"$hash\"; };"
    fi

    echo "}"
} >versions.nix.new
mv versions.nix.new versions.nix
