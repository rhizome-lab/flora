{
  description = "flora - Rhizome ecosystem monorepo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    spore.url = "github:rhizome-lab/spore";
    nursery.url = "github:rhizome-lab/nursery";
  };

  outputs = { self, nixpkgs, flake-utils, spore, nursery }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            spore.packages.${system}.default
            nursery.packages.${system}.default
            pkgs.bun
          ];
        };
      }
    );
}
