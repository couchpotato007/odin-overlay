# Nix Odin flake

This flake packages the Odin compiler as stable and nightly version

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
        ];
      };
    };
}
```
