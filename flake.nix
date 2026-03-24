{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, fenix, ... } @ inputs:
    inputs.flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      version = "0.2026.03.22.5e66329";
      hash = "sha256-/rSsNizWruoGgAJciXt8oWUfLUqqs8vBhcSKqxWzhl8=";

      arch = if system == "x86_64-linux" then "x86-linux"
             else if system == "aarch64-darwin" then "aarch64-macos"
             else if system == "x86_64-darwin" then "x86-macos"
             else throw "Unsupported system: ${system}";

      rust-toolchain = (fenix.packages.${system}.fromToolchainName {
        name = "1.94.0";
        sha256 = "sha256-qqF33vNuAdU5vua96VKVIwuc43j4EFeEXbjQ6+l4mO4=";
      }).completeToolchain;

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
        buildInputs = [ verus rust-toolchain ];
        shellHook = ''
          export RUSTUP_HOME=$(mktemp -d)
          mkdir -p "$RUSTUP_HOME/toolchains"
          ln -s "${rust-toolchain}" "$RUSTUP_HOME/toolchains/1.94.0-x86_64-unknown-linux-gnu"
          echo "Verus ${version} loaded."
        '';
      };
    });
}
