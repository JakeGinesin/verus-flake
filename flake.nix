{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    ...} @ inputs:
    inputs.flake-utils.lib.eachDefaultSystem (system:
    let 
      name = "verus-flake";
      src = ./.;
      pkgs = nixpkgs.legacyPackages.${system};

      verus = pkgs.stdenv.mkDerivation {
        pname = "verus";
        version = "0.2025.08.23.bb6fd4e";

        # get hash with nix-prefetch-url --unpack "https://github.com/verus-lang/verus/releases/download/release%2F0.2025.08.23.bb6fd4e/verus-0.2025.08.23.bb6fd4e-x86-linux.zip"

        src = pkgs.fetchzip {
          url =
            "https://github.com/verus-lang/verus/releases/download/release%2F0.2025.08.23.bb6fd4e/verus-0.2025.08.23.bb6fd4e-x86-linux.zip";
          sha256 = "0r69kkjlmf612gj9lx37x298278s899dngkhwb2j08sa9i0kv2ir";
        };

        installPhase = ''
          mkdir -p $out
          cp -r $src/* $out/

          mkdir -p $out/bin
          ln -s $out/verus $out/bin/verus
          ln -s $out/cargo-verus $out/bin/cargo-verus
          ln -s $out/rust_verify $out/bin/rust_verify
          ln -s $out/z3 $out/bin/z3
        '';

      };
    in {
      inherit name src;
      packages.default = verus;

      devShells.default = pkgs.mkShell {
        buildInputs = [
          verus
          pkgs.rustup
        ];

        packages = [
          pkgs.stdenv.cc.cc
          pkgs.zlib
          pkgs.openssl
          pkgs.glib
        ];

        shellHook = ''
          echo "wow verus"
        '';
      };
    }
  );
}
