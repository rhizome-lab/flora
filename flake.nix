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
        sporePkg = spore.packages.${system}.default;
      in
      {
        packages = {
          # Wisteria Lua source (for use with spore)
          wisteria-src = pkgs.stdenv.mkDerivation {
            pname = "wisteria-src";
            version = "0.1.0";
            src = ./wisteria;
            phases = [ "installPhase" ];
            installPhase = ''
              mkdir -p $out
              cp -r $src/* $out/
            '';
          };

          # Wisteria CLI wrapper
          # TODO: Needs spore-moss integration for full functionality
          wisteria = pkgs.writeShellScriptBin "wisteria" ''
            exec ${sporePkg}/bin/spore run ${self.packages.${system}.wisteria-src} -- "$@"
          '';

          default = self.packages.${system}.wisteria;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            sporePkg
            nursery.packages.${system}.default
            pkgs.bun
          ];
        };
      }
    );
}
