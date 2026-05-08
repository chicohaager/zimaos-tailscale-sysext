#!/usr/bin/env bash
#
# uninstall.sh — Remove the Tailscale sysext from ZimaOS
#
# Default: keeps /DATA/AppData/tailscale/ (the auth state). Use --purge to wipe.
#
# Usage:
#   sudo ./uninstall.sh             # remove sysext, keep state (re-installable without re-login)
#   sudo ./uninstall.sh --purge     # also wipe /DATA/AppData/tailscale/

set -euo pipefail

[[ "$(id -u)" -eq 0 ]] || { echo "✗ must run as root (use sudo)" >&2; exit 1; }

PURGE=0
[[ "${1:-}" = "--purge" ]] && PURGE=1

echo "═══ Tailscale-Sysext Uninstaller ═══"

# Logout from Tailscale (best-effort, ignore failures)
if systemctl is-active --quiet tailscaled.service 2>/dev/null && command -v tailscale >/dev/null; then
  echo "▶ tailscale logout (best-effort)"
  tailscale logout 2>/dev/null || true
fi

# Stop & disable
if systemctl list-unit-files tailscaled.service >/dev/null 2>&1; then
  echo "▶ Stopping & disabling tailscaled.service"
  systemctl disable --now tailscaled.service 2>/dev/null || true
fi

# Remove .raw (both possible locations) + refresh
for p in /var/lib/extensions/tailscale.raw /DATA/.extensions/tailscale.raw; do
  if [[ -f "$p" ]]; then
    echo "▶ Removing $p"
    rm -f "$p"
  fi
done

echo "▶ Refreshing sysext overlay"
systemd-sysext refresh || true
systemctl daemon-reload

# Optional state purge
if [[ $PURGE -eq 1 ]]; then
  if [[ -d /DATA/AppData/tailscale ]]; then
    echo "▶ --purge: removing /DATA/AppData/tailscale/"
    rm -rf /DATA/AppData/tailscale
  fi
else
  echo "  (kept /DATA/AppData/tailscale/ — re-running install.sh will reuse the auth state)"
fi

echo ""
echo "✓ Tailscale sysext removed."
