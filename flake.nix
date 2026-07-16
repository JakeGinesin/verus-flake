{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, ... } @ inputs:
    inputs.flake-utils.lib.eachDefaultSystem (system:
    let 
      pkgs = nixpkgs.legacyPackages.${system};

      version = "0.2026.07.12.0b42f4c";

      # match Verus release naming conventions
      arch = if system == "x86_64-linux" then "x86-linux"
             else if system == "aarch64-darwin" then "arm64-macos"
             else if system == "x86_64-darwin" then "x86-macos"
             else throw "Unsupported system: ${system}";

      # SRI hash of each release zip, keyed by Verus arch string
      # version + hashes are updated automatically by .github/workflows/update.yml
      hashes = {
        "x86-linux"   = "sha256-FQfn0350fPDaDcSH9V3LAkB/bfUTBunyAWZg05gO2uA=";
        "arm64-macos" = "sha256-Qngms121v3u9m3/mEfzOVMt2GbTYpsoRht63iTFLyKk=";
        "x86-macos"   = "sha256-behxXHNgabX766FxpSIXLiGaYSv0xr8qiJnfNA75Tak=";
      };

      verus = pkgs.stdenv.mkDerivation {
        pname = "verus";
        inherit version;

        src = pkgs.fetchzip {
          url = "https://github.com/verus-lang/verus/releases/download/release%2F${version}/verus-${version}-${arch}.zip";
          sha256 = hashes.${arch};
        };

        nativeBuildInputs = [ pkgs.makeWrapper ];

        # Verus locates its runtime root (verusroot) and helper binaries
        # (z3, rust_verify) relative to the real executable, so a bare symlink
        # in bin/ breaks it. so, makeWrapper is required
        installPhase = ''
          mkdir -p $out
          cp -r $src/* $out/
          mkdir -p $out/bin
          for bin in verus cargo-verus rust_verify z3; do
            makeWrapper $out/$bin $out/bin/$bin
          done
        '';

        meta.mainProgram = "verus";
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
