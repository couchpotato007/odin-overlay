{
  description = "Odin compiler overlay – stable, nightly and older releases";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    jailed-agents.url = "github:andersonjoseph/jailed-agents";
  };

  outputs = {
    self,
    nixpkgs,
    jailed-agents,
  }: let
    systems = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    forAllSystems = f: nixpkgs.lib.genAttrs systems f;
  in {
    overlays.default = import ./overlay.nix;

    packages = forAllSystems (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [self.overlays.default];
        };
      in
        # every buildable release under its tag name, e.g. .#dev-2025-06
        builtins.removeAttrs pkgs.odin-bin ["stable" "nightly"]
        // {
          default = pkgs.odin-bin.stable;
          odin = pkgs.odin-bin.stable;
          odin-nightly = pkgs.odin-bin.nightly;
          ols = pkgs.ols-bin.stable;
          ols-nightly = pkgs.ols-bin.nightly;
        }
    );

    devShells = forAllSystems (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [self.overlays.default];
        };
      in {
        default = pkgs.mkShell {
          name = "";

          packages = with pkgs; [
            (jailed-agents.lib.${system}.makeJailedClaudeCode {
              extraPkgs = with pkgs; [
                python3
              ];
              extraReadwriteDirs = ["~/.claude"];
              enableNix = true;
            })
          ];
        };
      }
    );
  };
}
