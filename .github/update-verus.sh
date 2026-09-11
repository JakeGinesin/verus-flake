#!/usr/bin/env bash
# update flake.nix to the latest Verus release (version + per-arch hashes).
# requires: curl, jq, nix (with nix-prefetch-url). Intended to run on linux.
set -euo pipefail

REPO="verus-lang/verus"
FLAKE="$(dirname "$0")/../flake.nix"

emit() { [ -n "${GITHUB_OUTPUT:-}" ] && echo "$1" >>"$GITHUB_OUTPUT"; return 0; }

# latest release tag looks like: release/0.2026.07.12.0b42f4c
TAG=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | jq -r .tag_name)
VERSION=${TAG#release/}
CURRENT=$(grep -oE 'version = "[^"]*";' "$FLAKE" | head -1 | sed -E 's/version = "([^"]*)";/\1/')
CURRENT_Z3=$(grep -oE '^\s*z3Version = "[^"]*";' "$FLAKE" | head -1 | sed -E 's/.*"([^"]*)".*/\1/')

echo "current: $CURRENT"
echo "latest:  $VERSION"

fetch_get_z3() {
  # the last dot-separated field of the version is the short commit sha
  local refs=( "refs/tags/${TAG}" "${VERSION##*.}" )
  local paths=( "source/tools/get-z3.sh" "tools/get-z3.sh" ".github/workflows/get-z3.sh" )
  local ref path out
  for ref in "${refs[@]}"; do
    for path in "${paths[@]}"; do
      if out=$(curl -fsSL "https://raw.githubusercontent.com/${REPO}/${ref}/${path}" 2>/dev/null); then
        printf '%s' "$out"
        return 0
      fi
    done
  done
  return 1
}

parse_z3_version() {
  local script="$1" v
  # an explicit assignment, e.g. z3_version="4.16.0" or Z3_VERSION=4.16.0
  v=$(printf '%s' "$script" \
        | grep -iEo 'z3[_-]?version[[:space:]]*=[[:space:]]*"?[0-9]+(\.[0-9]+)+' \
        | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)
  # otherwise an asset/tag name, e.g. z3-4.16.0-x64-glibc-2.39
  [ -n "$v" ] || v=$(printf '%s' "$script" \
        | grep -oE '\bz3-[0-9]+(\.[0-9]+)+' | sed 's/^z3-//' | head -1)
  [ -n "$v" ] || return 1
  printf '%s\n' "$v"
}

if ! GET_Z3=$(fetch_get_z3); then
  echo "error: could not fetch get-z3.sh for ${TAG}; has it moved?" >&2
  exit 1
fi
if ! Z3_VERSION=$(parse_z3_version "$GET_Z3"); then
  echo "error: could not parse a z3 version out of get-z3.sh; has its format changed?" >&2
  exit 1
fi
 
echo "z3 current:    $CURRENT_Z3"
echo "z3 expected:   $Z3_VERSION"

if [ "$CURRENT" = "$VERSION" ] && [ "$CURRENT_Z3" = "$Z3_VERSION" ]; then
  echo "Already up to date."
  emit "updated=false"
  exit 0
fi

get_hash() {
  local arch="$1"
  local url="https://github.com/${REPO}/releases/download/release%2F${VERSION}/verus-${VERSION}-${arch}.zip"
  nix hash convert --hash-algo sha256 --to sri "$(nix-prefetch-url --unpack "$url")"
}

get_z3_hash() {
  local url="https://github.com/Z3Prover/z3/archive/refs/tags/z3-${1}.tar.gz"
  nix hash convert --hash-algo sha256 --to sri "$(nix-prefetch-url --unpack "$url")"
}

export VERSION Z3_VERSION

if [ "$CURRENT" != "$VERSION" ]; then
  export H_LINUX=$(get_hash x86-linux)
  export H_ARM_MAC=$(get_hash arm64-macos)
  export H_X86_MAC=$(get_hash x86-macos)
 
  # perl -i is used instead of sed -i for portability (BSD/macOS vs GNU sed).
  # the version pattern is anchored so it cannot also hit `version = z3Version;`
  perl -i -pe 's|^(\s*)version = "[^"]*";|$1version = "$ENV{VERSION}";|' "$FLAKE"
  perl -i -pe 's|("x86-linux"\s*=\s*)"[^"]*";|$1"$ENV{H_LINUX}";|' "$FLAKE"
  perl -i -pe 's|("arm64-macos"\s*=\s*)"[^"]*";|$1"$ENV{H_ARM_MAC}";|' "$FLAKE"
  perl -i -pe 's|("x86-macos"\s*=\s*)"[^"]*";|$1"$ENV{H_X86_MAC}";|' "$FLAKE"
fi
 
if [ "$CURRENT_Z3" != "$Z3_VERSION" ]; then
  export Z3_HASH=$(get_z3_hash "$Z3_VERSION")
 
  perl -i -pe 's|^(\s*)z3Version = "[^"]*";|$1z3Version = "$ENV{Z3_VERSION}";|' "$FLAKE"
  # slurp mode, scoped to the z3 fetchFromGitHub, so this stays correct if
  # another `hash = "...";` is ever added elsewhere in the flake
  perl -0777 -i -pe 's|(repo = "z3";.*?hash = ")[^"]*(")|$1$ENV{Z3_HASH}$2|s' "$FLAKE"
 
  echo "z3 bumped: $CURRENT_Z3 -> $Z3_VERSION"
  emit "z3_updated=true"
fi
 
echo "Updated flake.nix: $CURRENT -> $VERSION (z3 $CURRENT_Z3 -> $Z3_VERSION)"
emit "updated=true"
emit "version=${VERSION}"
emit "previous=${CURRENT}"
emit "z3=${Z3_VERSION}"
emit "previous_z3=${CURRENT_Z3}"
