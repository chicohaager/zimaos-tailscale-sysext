#!/usr/bin/env bash
# Builds the image three times and compares the bytes: once with umask 022 and no group write bit
# on the checked-out files (as in a CI checkout), once with umask 002 and group-writable files
# (a desktop checkout), once with umask 077 (a root shell of the sudo helper on ZimaOS). Different bytes mean a release image depends on the machine that
# built it, or on the time of the build (measured 2026-10-26).
#   tools/check-reproducible.sh [amd64|arm64]
#   TAILSCALE_VERSION=1.104.2 tools/check-reproducible.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ARCH="${1:-amd64}"
OUT="dist/tailscale-$ARCH.raw"
mkdir -p dist
# one Tailscale version for both builds, from the stable manifest (as tools/release-assets.sh)
if [[ -z "${TAILSCALE_VERSION:-}" ]]; then
  MANIFEST="$(curl -fsSL --retry 3 'https://pkgs.tailscale.com/stable/?mode=json')"
  TAILSCALE_VERSION="$(grep -oE "tailscale_[0-9]+\.[0-9]+\.[0-9]+_${ARCH}\.tgz" <<<"$MANIFEST" \
    | sed -n '1p' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
fi
export TAILSCALE_VERSION
build() { ARCH="$ARCH" OUT="$PWD/$OUT" ./build.sh > /dev/null; }
modes=$(mktemp); trap 'rm -f "$modes"' EXIT
git ls-files -z | xargs -0 stat -c '%a %n' > "$modes"
git ls-files -z | xargs -0 chmod g-w
(umask 022 && build)
a=$(sha256sum "$OUT" | cut -d' ' -f1)
git ls-files -z | xargs -0 chmod g+w
(umask 002 && build)
b=$(sha256sum "$OUT" | cut -d' ' -f1)
git ls-files -z | xargs -0 chmod go-rwx
(umask 077 && build)
c=$(sha256sum "$OUT" | cut -d' ' -f1)
# the checked-out files get their modes back
while read -r mode f; do chmod "$mode" "$f"; done < "$modes"
if [ "$a" != "$b" ] || [ "$a" != "$c" ]; then
  echo "not reproducible: $OUT is $a with umask 022, $b with umask 002 and group-writable files, $c with umask 077" >&2
  exit 1
fi
echo "reproducible: $OUT $a (umask 022, 002 and 077, Tailscale $TAILSCALE_VERSION)"
