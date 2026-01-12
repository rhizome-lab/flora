{
  description = "flora - Rhizome ecosystem monorepo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    spore.url = "github:rhizome-lab/spore";
  };

  outputs = { self, nixpkgs, flake-utils, spore }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell rec {
          buildInputs = [
            spore.packages.${system}.default
            pkgs.bun
          ];
        };
      }
    );
}
