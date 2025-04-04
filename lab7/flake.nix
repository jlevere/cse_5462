{
  description = "A Nix-flake-based development environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    zig-overlay.url = "github:mitchellh/zig-overlay";
    zig-overlay.inputs.nixpkgs.follows = "nixpkgs";
    zls.url = "github:zigtools/zls";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    ...
  }: let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;

    zig = inputs.zig-overlay.packages.x86_64-linux."0.14.0";
    zig-build = inputs.zig-overlay.packages.x86_64-linux."master-2025-04-03";
    zls = inputs.zls.packages.x86_64-linux.zls.overrideAttrs (old: {
      nativeBuildInputs = [zig-build];
    });
  in {
    devShells.x86_64-linux.default = pkgs.mkShell {
      packages = with pkgs; [zig zls vhs harper];
    };

    devShells.x86_64-linux.build = pkgs.mkShell {
      packages = [zig];
    };
  };
}
