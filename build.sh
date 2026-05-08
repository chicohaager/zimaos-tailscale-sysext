#!/usr/bin/env bash
#
# build.sh — Build a systemd-sysext extension for Tailscale on ZimaOS
#
# Output: ./tailscale.raw  (squashfs, gzip-compressed)
#
# Usage:
#   ./build.sh                    # uses TAILSCALE_VERSION env var or queries latest
#   TAILSCALE_VERSION=1.96.4 ./build.sh
#   ARCH=amd64 ./build.sh         # arm64 also supported by Tailscale upstream
#
# Reproducibility: pin TAILSCALE_VERSION to get a deterministic .raw.

set -euo pipefail

ARCH="${ARCH:-amd64}"
WORK="$(mktemp -d -t ts-sysext-XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# ── Resolve Tailscale version ────────────────────────────────────────────
if [[ -z "${TAILSCALE_VERSION:-}" ]]; then
  echo "▶ Querying latest Tailscale stable release..."
  TAILSCALE_VERSION="$(curl -fsSL https://api.github.com/repos/tailscale/tailscale/releases/latest \
    | grep -oE '"tag_name":\s*"v[0-9.]+"' | head -1 | grep -oE '[0-9.]+')"
fi
[[ -n "$TAILSCALE_VERSION" ]] || { echo "✗ failed to resolve Tailscale version" >&2; exit 1; }
echo "▶ Tailscale version: $TAILSCALE_VERSION ($ARCH)"

# ── Download upstream static tarball + verify SHA256 ─────────────────────
TARBALL="tailscale_${TAILSCALE_VERSION}_${ARCH}.tgz"
URL="https://pkgs.tailscale.com/stable/${TARBALL}"
SHA_URL="${URL}.sha256"

echo "▶ Downloading $URL"
curl -fsSL --retry 3 -o "$WORK/$TARBALL" "$URL"

echo "▶ Verifying SHA256 against ${SHA_URL}"
EXPECTED_SHA="$(curl -fsSL --retry 3 "$SHA_URL" | tr -d '[:space:]')"
[[ "$EXPECTED_SHA" =~ ^[0-9a-f]{64}$ ]] \
  || { echo "✗ couldn't fetch a valid sha256 from $SHA_URL" >&2; exit 1; }
ACTUAL_SHA="$(sha256sum "$WORK/$TARBALL" | cut -d' ' -f1)"
[[ "$ACTUAL_SHA" = "$EXPECTED_SHA" ]] \
  || { echo "✗ SHA256 mismatch — refusing to use tarball" >&2;
       echo "  expected: $EXPECTED_SHA" >&2;
       echo "  actual:   $ACTUAL_SHA"   >&2;
       exit 1; }
echo "  ✓ SHA256 verified ($ACTUAL_SHA)"

tar -C "$WORK" -xzf "$WORK/$TARBALL"
SRC="$WORK/tailscale_${TAILSCALE_VERSION}_${ARCH}"
[[ -x "$SRC/tailscaled" ]] || { echo "✗ tailscaled missing in tarball" >&2; exit 1; }

# ── Lay out sysext root ──────────────────────────────────────────────────
ROOT="$WORK/root"
mkdir -p \
  "$ROOT/usr/bin" \
  "$ROOT/usr/sbin" \
  "$ROOT/usr/lib/systemd/system/multi-user.target.wants" \
  "$ROOT/usr/lib/extension-release.d"

install -m 0755 "$SRC/tailscale"  "$ROOT/usr/bin/tailscale"
install -m 0755 "$SRC/tailscaled" "$ROOT/usr/bin/tailscaled"
ln -sf ../bin/tailscaled "$ROOT/usr/sbin/tailscaled"

# Service unit (bundled in repo)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
install -m 0644 "$SCRIPT_DIR/systemd/tailscaled.service" \
  "$ROOT/usr/lib/systemd/system/tailscaled.service"
ln -sf ../tailscaled.service \
  "$ROOT/usr/lib/systemd/system/multi-user.target.wants/tailscaled.service"

# Extension-release marker (matches existing ZimaOS sysext convention)
printf 'ID=_any\n' > "$ROOT/usr/lib/extension-release.d/extension-release.tailscale"

# ── Build SquashFS (gzip — kernel has no SQUASHFS_ZSTD on ZimaOS) ────────
OUT="$SCRIPT_DIR/tailscale.raw"
rm -f "$OUT"
echo "▶ Packing $OUT"
mksquashfs "$ROOT" "$OUT" \
  -comp gzip \
  -all-root \
  -noappend \
  -no-progress \
  -no-xattrs >/dev/null

SIZE_HUMAN="$(du -h "$OUT" | cut -f1)"
SHA256="$(sha256sum "$OUT" | cut -d' ' -f1)"
echo ""
echo "✓ Built: $OUT"
echo "  Tailscale: $TAILSCALE_VERSION ($ARCH)"
echo "  Size:      $SIZE_HUMAN"
echo "  SHA256:    $SHA256"
