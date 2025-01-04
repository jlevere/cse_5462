{
  description = "A Nix-flake-based development enviroment for CSE 5462";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    harper = {
      url = "github:grantlemons/harper";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    harper,
  }: let
    supportedSystems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forEachSupportedSystem = f:
      nixpkgs.lib.genAttrs supportedSystems (system:
        f {
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        });
  in {
    devShells = forEachSupportedSystem ({pkgs}: {
      default =
        pkgs.mkShell.override
        {
          # Override stdenv in order to change compiler:
          # stdenv = pkgs.clangStdenv;
        }
        {
          packages = with pkgs;
            [
              codespell
              gcc
              ctags
              valgrind

              typst
              (pkgs.rustPlatform.buildRustPackage {
                pname = "harper-ls";
                version = "master";

                src = harper;

                cargoLock = null;
                cargoBuild = true;
                cargoHash = "sha256-2IRM7Ttaw30c99U39+YqL9GzCEpXfTrmBvdxD4FPbuM=";
              })
            ]
            ++ (
              if system == "aarch64-darwin"
              then []
              else [gdb]
            );
        };
    });
  };
}
