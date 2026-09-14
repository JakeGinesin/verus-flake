{
  description = "Verus: verified Rust for low-level systems code (binary releases)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, ... } @ inputs:
    inputs.flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      lib = pkgs.lib;

      version = "0.2026.09.13.671956e";

      # match Verus release naming conventions
      arch = if system == "x86_64-linux" then "x86-linux"
             else if system == "aarch64-darwin" then "arm64-macos"
             else if system == "x86_64-darwin" then "x86-macos"
             else throw "Unsupported system: ${system}";

      # SRI hash of each release zip, keyed by Verus arch string
      # version + hashes are updated automatically by .github/workflows/update.yml
      hashes = {
        "x86-linux"   = "sha256-lMLLfsueqolx2e3VtCtAmdAYAajOsoJOSVjbjzhzoQQ=";
        "arm64-macos" = "sha256-UUAj9w7Dv0Qkew31NmQJc5VpkfFsMmqw/cBWIN1PSoQ=";
        "x86-macos"   = "sha256-4TuSfjH5kcx8Jsnyyj5yg/i37mPiYjBYPasNfBs83IE=";
      };

      programs = [ "verus" "cargo-verus" "rust_verify" ];

      z3Version = "4.16.0";

      z3 = pkgs.z3.overrideAttrs (old: {
        version = z3Version;
        src = pkgs.fetchFromGitHub {
          owner = "Z3Prover";
          repo = "z3";
          tag = "z3-${z3Version}";
          hash = "sha256-DnhX3kxggnFmyYwXEPBsBA1rh4oor1oIJR5TMJk/jvc=";
        };
      });

      runtimeLibs = lib.optionalString pkgs.stdenv.isLinux
        "--prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ pkgs.zlib pkgs.stdenv.cc.cc.lib ]}";

      verus = pkgs.stdenv.mkDerivation {
        pname = "verus";
        inherit version;

        src = pkgs.fetchzip {
          url = "https://github.com/verus-lang/verus/releases/download/release%2F${version}/verus-${version}-${arch}.zip";
          sha256 = hashes.${arch};
        };

        dontUnpack = true;
        dontConfigure = true;
        dontBuild = true;

        nativeBuildInputs = [ pkgs.makeWrapper ]
          ++ lib.optional pkgs.stdenv.isLinux pkgs.autoPatchelfHook;

        autoPatchelfIgnoreMissingDeps = [ "librustc_driver-*.so" ];

        buildInputs = lib.optionals pkgs.stdenv.isLinux [
          pkgs.stdenv.cc.cc.lib
          pkgs.zlib
        ];

        installPhase = ''
          runHook preInstall

          mkdir -p $out/bin
          # `$src/.` rather than `$src/*` so dotfiles (.verus-root) come along
          cp -r $src/. $out/
          # store copies come back read-only; autoPatchelf needs write
          chmod -R u+w $out

          # remove build and incremental, useless at runtime for verus
          rm -rf $out/build $out/incremental
          # same for bump_crate_versions
          rm -f $out/bump_crate_versions $out/bump_crate_versions.d \
                $out/deps/bump_crate_versions-*

          rm -rf $out/z3
          ln -s ${z3}/bin/z3 $out/z3

          for bin in ${toString programs}; do
            makeWrapper $out/$bin $out/bin/$bin \
              --set-default VERUS_Z3_PATH ${z3}/bin/z3 \
              ${runtimeLibs}
          done

          runHook postInstall
        '';

        meta = {
          description = "Verified Rust for low-level systems code";
          homepage = "https://github.com/verus-lang/verus";
          license = [ lib.licenses.mit lib.licenses.asl20 ];
          platforms = [ "x86_64-linux" "aarch64-darwin" "x86_64-darwin" ];
          sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
          mainProgram = "verus";
        };
      };
    in {
      packages = {
        default = verus;
        inherit verus;
      };

      devShells.default = pkgs.mkShell {
        packages = [ verus pkgs.rustup ];
        shellHook = ''
          echo "Verus ${version} loaded (z3 ${z3.version})."

          # Verus is not self-contained since it needs the matching rustup toolchain
          # (recorded in version.json) installed to actually run. The recorded
          # value has a "(overridden by environment variable ...)" suffix because
          # of how the release is built, so stop at the first space.
          toolchain=$(sed -n 's/.*"toolchain"[^"]*"\([^" ]*\).*/\1/p' ${verus}/version.json)
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
