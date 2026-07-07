# Nix Odin flake

this flake packages the Odin compiler

I tested this only on `x86_64-linux`

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
