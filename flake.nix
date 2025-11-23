{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, ... } @ inputs:
    inputs.flake-utils.lib.eachDefaultSystem (system:
    let 
      pkgs = nixpkgs.legacyPackages.${system};

      version = "0.2025.11.15.db81a74";
      hash = "0iijcvs8rlp4gx5y4g4z1wv8nqyz8nb4wlgk71rbmg2s084wcrz9";

      # match Verus release naming conventions
      arch = if system == "x86_64-linux" then "x86-linux"
             else if system == "aarch64-darwin" then "aarch64-macos"
             else if system == "x86_64-darwin" then "x86-macos"
             else throw "Unsupported system: ${system}";

      verus = pkgs.stdenv.mkDerivation {
        pname = "verus";
        inherit version;

        src = pkgs.fetchzip {
          url = "https://github.com/verus-lang/verus/releases/download/release%2F${version}/verus-${version}-${arch}.zip";
          sha256 = hash;
        };

        installPhase = ''
          mkdir -p $out
          cp -r $src/* $out/
          mkdir -p $out/bin
          for bin in verus cargo-verus rust_verify z3; do
            ln -s $out/$bin $out/bin/$bin
          done
        '';
      };
    in {
      packages.default = verus;

      devShells.default = pkgs.mkShell {
        buildInputs = [ verus ];
        shellHook = ''
          echo "Verus ${version} loaded."
        '';
      };
    }
  );
}
