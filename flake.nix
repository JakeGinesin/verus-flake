{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, ... } @ inputs:
    inputs.flake-utils.lib.eachDefaultSystem (system:
    let 
      pkgs = nixpkgs.legacyPackages.${system};

      version = "0.2026.08.15.7d4628a";

      # match Verus release naming conventions
      arch = if system == "x86_64-linux" then "x86-linux"
             else if system == "aarch64-darwin" then "arm64-macos"
             else if system == "x86_64-darwin" then "x86-macos"
             else throw "Unsupported system: ${system}";

      # SRI hash of each release zip, keyed by Verus arch string
      # version + hashes are updated automatically by .github/workflows/update.yml
      hashes = {
        "x86-linux"   = "sha256-7oIjriBKchgZzM3xSswgVyjvXqy5u19cI6yTCMjV7ck=";
        "arm64-macos" = "sha256-9q69GKvBow027R2eygPtq3u2yC2DB4wHpgyxiVP8U7s=";
        "x86-macos"   = "sha256-Hg2ODHEdZKKJJLhiz3Hsa9TQaYnscoGo2sgWfmLKxb8=";
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
        buildInputs = [ verus pkgs.rustup ];
        shellHook = ''
          echo "Verus ${version} loaded."

          # Verus is not self-contained since it needs the matching rustup toolchain
          # (recorded in version.json) installed to actually run.
          toolchain=$(sed -n 's/.*"toolchain"[^"]*"\([^"]*\)".*/\1/p' ${verus}/version.json)
          if [ -n "$toolchain" ] && ! rustup toolchain list 2>/dev/null | grep -q "$toolchain"; then
            echo ""
            echo "Verus requires the Rust toolchain '$toolchain', which is not installed."
            echo "Install it with:"
            echo "  rustup install $toolchain"
          fi
        '';
      };
    }
  );
}
