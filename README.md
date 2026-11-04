# Nix Odin flake

This flake packages the Odin compiler and ols as stable and nightly versions,
plus older Odin releases (similar to mitchellh/zig-overlay).

Odin releases are available from `dev-2024-05` on: older ones need LLVM <= 17,
which is no longer packaged in nixpkgs.

The pinned sources live in `sources.json` and are refreshed daily by
`./update.sh` (run via GitHub Actions).

## Packages

| overlay attribute         | flake package           | description                          |
| ------------------------- | ----------------------- | ------------------------------------ |
| `odin-bin.stable`         | `odin`, `default`       | newest Odin release tag              |
| `odin-bin.nightly`        | `odin-nightly`          | Odin `master`                        |
| `odin-bin."dev-YYYY-MM"`  | `dev-YYYY-MM`           | a specific release, e.g. `dev-2025-06` |
| `ols-bin.stable`          | `ols`                   | newest ols tag, built with the matching Odin release |
| `ols-bin.nightly`         | `ols-nightly`           | ols `master`, built with nightly Odin |

```sh
nix run github:couchpotato007/odin-overlay#dev-2025-06 -- version
```

`vendor:raylib` links against the system raylib/raygui (`system:raylib`), so
add `raylib` (and raygui) to your shell when you use it.

I tested this only on `x86_64-linux`

currently there is no cache for the compiler but the build time is very short

## Usage

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    odin-overlay = {
      url = "github:couchpotato007/odin-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      odin-overlay,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ odin-overlay.overlays.default ];
      };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          # stable release
          odin-bin.stable
          # nightly release
          # odin-bin.nightly
          # a specific release
          # odin-bin."dev-2025-06"
          # stable release
          ols-bin.stable
          # nightly release
          # ols-bin.nightly
        ];
      };
    };
}
```
