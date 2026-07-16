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

echo "current: $CURRENT"
echo "latest:  $VERSION"

if [ "$CURRENT" = "$VERSION" ]; then
  echo "Already up to date."
  emit "updated=false"
  exit 0
fi

get_hash() {
  local arch="$1"
  local url="https://github.com/${REPO}/releases/download/release%2F${VERSION}/verus-${VERSION}-${arch}.zip"
  nix hash convert --hash-algo sha256 --to sri "$(nix-prefetch-url --unpack "$url")"
}

export VERSION
export H_LINUX=$(get_hash x86-linux)
export H_ARM_MAC=$(get_hash arm64-macos)
export H_X86_MAC=$(get_hash x86-macos)

# perl -i is used instead of sed -i for portability (BSD/macOS vs GNU sed)
perl -i -pe 's|version = "[^"]*";|version = "$ENV{VERSION}";|' "$FLAKE"
perl -i -pe 's|("x86-linux"\s*=\s*)"[^"]*";|$1"$ENV{H_LINUX}";|' "$FLAKE"
perl -i -pe 's|("arm64-macos"\s*=\s*)"[^"]*";|$1"$ENV{H_ARM_MAC}";|' "$FLAKE"
perl -i -pe 's|("x86-macos"\s*=\s*)"[^"]*";|$1"$ENV{H_X86_MAC}";|' "$FLAKE"

echo "Updated flake.nix: $CURRENT -> $VERSION"
emit "updated=true"
emit "version=${VERSION}"
emit "previous=${CURRENT}"
