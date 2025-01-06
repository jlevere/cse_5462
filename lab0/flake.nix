{
  description = "A Nix-flake-based Go 1.23 development environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    zig-overlay.url = "github:mitchellh/zig-overlay";
    zig-overlay.inputs.nixpkgs.follows = "nixpkgs";
    zls-overlay.url = "github:zigtools/zls";
  };

  outputs = {
    self,
    nixpkgs,
    zig-overlay,
    zls-overlay,
    ...
  }: let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    zig = zig-overlay.packages.x86_64-linux.master;
    zls =
      zls-overlay.packages.x86_64-linux.zls.overrideAttrs
      (old: {nativeBuildInputs = [zig];});
  in {
    devShells.x86_64-linux.default = pkgs.mkShell {
      packages = with pkgs; [zig zls];
    };
  };
}
