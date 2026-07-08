{
  description = "Odin compiler overlay – stable, nightly ";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;
    in
    {
      overlays.default = import ./overlay.nix;

      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
          };
        in
        {
          default = pkgs.odin-bin.stable;
          odin = pkgs.odin-bin.stable;
          odin-nightly = pkgs.odin-bin.nightly;
          ols = pkgs.ols-bin.stable;
          ols-nightly = pkgs.ols-bin.nightly;
        }
      );
    };
}
