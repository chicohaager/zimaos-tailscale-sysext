#!/usr/bin/env bash
#
# release-assets.sh — build the release assets for both architectures:
#   dist/tailscale-amd64.raw(.sha256)  dist/tailscale-arm64.raw(.sha256)
#
# One Tailscale version for both images: resolved once from the stable
# manifest (or TAILSCALE_VERSION=… to pin), then handed to build.sh twice.
# The .sha256 files have the `sha256sum -c` format with the bare file name,
# which is what the lintux-modkit installer verifies after download.
#
#   tools/release-assets.sh
#   TAILSCALE_VERSION=1.98.8 tools/release-assets.sh

set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${TAILSCALE_VERSION:-}" ]]; then
  MANIFEST="$(curl -fsSL --retry 3 'https://pkgs.tailscale.com/stable/?mode=json')"
  TAILSCALE_VERSION="$(grep -oE 'tailscale_[0-9]+\.[0-9]+\.[0-9]+_amd64\.tgz' <<<"$MANIFEST" \
    | sed -n '1p' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
fi
[[ "$TAILSCALE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || { echo "✗ no valid Tailscale version ('$TAILSCALE_VERSION')" >&2; exit 1; }

mkdir -p dist
for arch in amd64 arm64; do
  out="dist/tailscale-$arch.raw"
  TAILSCALE_VERSION="$TAILSCALE_VERSION" ARCH="$arch" OUT="$PWD/$out" ./build.sh
  ( cd dist && sha256sum "tailscale-$arch.raw" > "tailscale-$arch.raw.sha256" )
done
echo ""
echo "✓ module $(tr -d '[:space:]' <VERSION), Tailscale $TAILSCALE_VERSION"
cat dist/*.sha256
