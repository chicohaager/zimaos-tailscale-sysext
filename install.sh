#!/usr/bin/env bash
#
# install.sh — One-shot Tailscale-Sysext installer for ZimaOS
#
# Run AS ROOT (or via sudo) directly on a ZimaOS host:
#   sudo ./install.sh
#
# Or piped (verify the URL first!):
#   curl -fsSL https://raw.githubusercontent.com/<user>/<repo>/main/install.sh | sudo bash
#
# What it does:
#   1. Sanity-checks ZimaOS host (kernel modules, squashfs compression, paths)
#   2. Builds tailscale.raw locally via build.sh (uses upstream tailscale tarball)
#   3. Installs to /var/lib/extensions/ (persistent bind-mount)
#   4. Refreshes systemd-sysext, enables tailscaled.service
#   5. Prints `tailscale up` instructions

set -euo pipefail

[[ "$(id -u)" -eq 0 ]] || { echo "✗ must run as root (use sudo)" >&2; exit 1; }

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/chicohaager/zimaos-tailscale-sysext/main}"
TAILSCALE_VERSION="${TAILSCALE_VERSION:-}"   # empty → build.sh resolves latest
ARCH="${ARCH:-amd64}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || pwd)"

# ── Sanity checks ────────────────────────────────────────────────────────
echo "═══ ZimaOS Tailscale-Sysext Installer ═══"
echo ""
echo "▶ Host:    $(hostname) ($(uname -m), kernel $(uname -r))"
[[ -f /etc/os-release ]] && echo "▶ OS:      $(. /etc/os-release; echo "$PRETTY_NAME")"
[[ "$(uname -m)" = "x86_64" && "$ARCH" = "amd64" ]] || \
  echo "⚠ Architecture mismatch: kernel=$(uname -m), build target=$ARCH (you may need ARCH=arm64)"

# Tools
for t in mksquashfs curl tar systemctl systemd-sysext; do
  command -v "$t" >/dev/null || { echo "✗ missing tool: $t" >&2; exit 1; }
done

# Kernel: gzip squashfs support
zcat /proc/config.gz 2>/dev/null | grep -q '^CONFIG_SQUASHFS_ZLIB=y' \
  || echo "⚠ kernel SQUASHFS_ZLIB not detected — gzip mount may fail"

# IPv6 capability audit (informational — sysext can't fix kernel configs)
if zcat /proc/config.gz 2>/dev/null | grep -qE '^# CONFIG_IPV6_MULTIPLE_TABLES is not set'; then
  echo ""
  echo "⚠ IPv6 limitation detected:"
  echo "    CONFIG_IPV6_MULTIPLE_TABLES is not set in this kernel."
  echo "    Tailscale will disable IPv6 tunneling at runtime — IPv4 mesh works fine,"
  echo "    but IPv6-over-tailnet is unavailable until IceWhale enables this kernel"
  echo "    config. See: mod-store/ICEWHALE_KERNEL_REQUEST.md"
  echo ""
fi

# /var/lib/extensions writable & a directory
[[ -d /var/lib/extensions ]] || { echo "✗ /var/lib/extensions missing" >&2; exit 1; }

# Conflict check: existing tailscale daemons / docker container
if pgrep -f '/usr/sbin/tailscaled\|^tailscaled' >/dev/null; then
  echo "⚠ a tailscaled process is already running:"
  pgrep -af 'tailscaled' || true
  echo "  This installer will replace it with the systemd-managed sysext daemon."
  read -r -p "  Continue? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || { echo "aborted"; exit 0; }
fi

# Existing docker container?
if command -v docker >/dev/null && DOCKER_CONFIG=/DATA/.docker docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx tailscale; then
  echo "⚠ a docker container named 'tailscale' exists. It will be stopped (not removed)."
  DOCKER_CONFIG=/DATA/.docker docker stop tailscale 2>/dev/null || true
  DOCKER_CONFIG=/DATA/.docker docker update --restart=no tailscale 2>/dev/null || true
fi

# ── Build ────────────────────────────────────────────────────────────────
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [[ -x "$SCRIPT_DIR/build.sh" && -d "$SCRIPT_DIR/systemd" ]]; then
  echo "▶ Local checkout detected — building from $SCRIPT_DIR"
  ( cd "$SCRIPT_DIR" && TAILSCALE_VERSION="$TAILSCALE_VERSION" ARCH="$ARCH" ./build.sh )
  RAW="$SCRIPT_DIR/tailscale.raw"
else
  echo "▶ Fetching build artifacts from $REPO_RAW"
  curl -fsSL "$REPO_RAW/build.sh"                         -o "$WORK/build.sh"
  mkdir -p "$WORK/systemd"
  curl -fsSL "$REPO_RAW/systemd/tailscaled.service"       -o "$WORK/systemd/tailscaled.service"
  chmod +x "$WORK/build.sh"
  ( cd "$WORK" && TAILSCALE_VERSION="$TAILSCALE_VERSION" ARCH="$ARCH" ./build.sh )
  RAW="$WORK/tailscale.raw"
fi
[[ -s "$RAW" ]] || { echo "✗ build failed — no .raw produced" >&2; exit 1; }

# ── Deploy ───────────────────────────────────────────────────────────────
echo ""
echo "▶ Installing $RAW → /var/lib/extensions/tailscale.raw"
install -m 0644 "$RAW" /var/lib/extensions/tailscale.raw

echo "▶ Refreshing sysext overlay"
systemd-sysext refresh

echo "▶ Enabling tailscaled.service"
systemctl daemon-reload
systemctl enable --now tailscaled.service

# ── Verify ───────────────────────────────────────────────────────────────
sleep 2
echo ""
echo "═══ Status ═══"
systemctl --no-pager status tailscaled.service | sed -n '1,8p' || true
echo ""

if /usr/bin/tailscale status --json 2>/dev/null | grep -q '"BackendState": *"NeedsLogin"'; then
  echo ""
  echo "▶ Tailscale is installed but not yet authenticated. Next step:"
  echo ""
  echo "    sudo tailscale up"
  echo ""
  echo "  (then open the printed login URL in your browser)"
elif /usr/bin/tailscale status >/dev/null 2>&1; then
  echo "✓ Tailscale is up and connected:"
  /usr/bin/tailscale status | head -5
else
  echo "⚠ tailscaled started but status check inconclusive — see 'journalctl -u tailscaled' for details"
fi

echo ""
echo "Done. State persists at /DATA/AppData/tailscale/."
