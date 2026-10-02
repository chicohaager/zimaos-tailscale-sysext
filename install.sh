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

# IPv6 capability audit (informational — sysext can't fix kernel configs).
# Kernel 6.18.9 (ZimaOS v1.6.2-beta2 and later, incl. stable v1.7.0) enables all of
# these; kernel 6.12.25 (v1.6.1) did not.
# We capture the kernel config once and run pure-bash checks (no pipe-in-if,
# which can interact subtly with `set -o pipefail`).
KCFG=""
if [[ -r /proc/config.gz ]]; then
  KCFG="$(zcat /proc/config.gz 2>/dev/null || true)"
elif [[ -r "/boot/config-$(uname -r)" ]]; then
  KCFG="$(cat "/boot/config-$(uname -r)" 2>/dev/null || true)"
fi

if [[ -n "$KCFG" ]]; then
  # Kernel: gzip squashfs support. Checked against the captured config, not through
  # a pipe — `zcat … | grep -q` can lose the race and die of SIGPIPE, which under
  # `set -o pipefail` turns a *present* flag into a bogus "not detected" warning.
  grep -qE '^CONFIG_SQUASHFS_ZLIB=y' <<<"$KCFG" \
    || echo "⚠ kernel SQUASHFS_ZLIB not detected — gzip mount may fail"

  IPV6_MISSING=()
  # Each entry: <CONFIG_NAME>[,<EQUIVALENT_NAME>…]|<purpose>
  # An entry counts as satisfied if ANY of its names is =y or =m. Second names are
  # kernel-side equivalents, not nice-to-haves: CONFIG_IP6_NF_TARGET_MASQUERADE has
  # been a pure backwards-compat alias since Linux 5.2 that just selects
  # CONFIG_NETFILTER_XT_TARGET_MASQUERADE (see net/ipv6/netfilter/Kconfig), so
  # checking only the old name reports a missing feature that is actually present.
  for entry in \
      "CONFIG_IPV6_MULTIPLE_TABLES|🔴 hard blocker — Tailscale auto-disables IPv6 tunneling without it" \
      "CONFIG_IPV6_SUBTREES|🟡 source-prefix IPv6 routes" \
      "CONFIG_NETFILTER_XT_TARGET_MARK|🟡 iptables -j MARK target — tags tunneled packets" \
      "CONFIG_NETFILTER_XT_TARGET_MASQUERADE,CONFIG_IP6_NF_TARGET_MASQUERADE|🟡 IPv6 subnet-router masquerading" ; do
    names="${entry%%|*}"
    purpose="${entry#*|}"
    # Treat both "# … is not set" and "absent entirely" as missing.
    found=0
    for name in ${names//,/ }; do
      if grep -qE "^${name}=[ym]$" <<<"$KCFG"; then found=1; break; fi
    done
    if (( ! found )); then
      IPV6_MISSING+=("    • ${names//,/ or }  ${purpose}")
    fi
  done

  if (( ${#IPV6_MISSING[@]} > 0 )); then
    echo ""
    echo "⚠  IPv6 capability audit — ${#IPV6_MISSING[@]} kernel config(s) missing on this ZimaOS host:"
    echo ""
    printf '%s\n' "${IPV6_MISSING[@]}"
    echo ""
    echo "    Effect at runtime: Tailscale will log"
    echo "      'router: disabling tunneled IPv6 due to system IPv6 config'"
    echo "    and run IPv4-only inside the tailnet."
    echo ""
    echo "    👉 This is a ZimaOS kernel-image issue, NOT a bug in this module —"
    echo "       a sysext cannot patch a kernel image."
    echo ""
    echo "    📝 Fix: upgrade ZimaOS. Kernel 6.18.9 (v1.6.2-beta2 and later, incl."
    echo "       stable v1.7.0) ships these flags; 6.12.25 (v1.6.1) does not."
    echo "       Background: mod-store/ICEWHALE_KERNEL_REQUEST.md"
    echo ""
    echo "    Continuing — IPv4 mesh, subnet-router and exit-node work fine."
    echo ""
  else
    echo "✓ IPv6 capability audit: all kernel flags present — Tailscale enables tunneled IPv6"
  fi
fi

# /var/lib/extensions writable & a directory
[[ -d /var/lib/extensions ]] || { echo "✗ /var/lib/extensions missing" >&2; exit 1; }

# Conflict check: existing tailscale daemons / docker container
if pgrep -x tailscaled >/dev/null; then
  echo "⚠ a tailscaled process is already running:"
  pgrep -af 'tailscaled' || true
  echo "  This installer will replace it with the systemd-managed sysext daemon."
  # Never read the answer from stdin blindly: in the documented piped install
  # (`curl … | sudo bash`) stdin carries the *script*, so a bare `read` would
  # swallow the next line of install.sh and use it as the answer. Ask the
  # terminal directly, and if there is none (piped, cron, ssh without a tty),
  # say so and continue — re-running the installer to update is a normal case,
  # and the daemon it replaces is the one it installed.
  ans=""
  if [[ -t 0 ]]; then
    read -r -p "  Continue? [y/N] " ans
  elif { : </dev/tty; } 2>/dev/null; then
    printf '  Continue? [y/N] '
    read -r ans </dev/tty
  else
    echo "  (no terminal available for a prompt — continuing)"
    ans=y
  fi
  [[ "$ans" =~ ^[Yy]$ ]] || { echo "aborted"; exit 0; }
fi

# Existing docker container? Capture the list first: `docker ps | grep -q` under
# `set -o pipefail` can return 141 when grep exits on the match before docker is
# done writing — a *found* container would then read as "not there" and stay up.
DOCKER_NAMES=""
if command -v docker >/dev/null; then
  DOCKER_NAMES="$(DOCKER_CONFIG=/DATA/.docker docker ps -a --format '{{.Names}}' 2>/dev/null || true)"
fi
if grep -qx tailscale <<<"$DOCKER_NAMES"; then
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
  UNIT_SRC="$SCRIPT_DIR/systemd"
else
  echo "▶ Fetching build artifacts from $REPO_RAW"
  curl -fsSL "$REPO_RAW/build.sh"                            -o "$WORK/build.sh"
  mkdir -p "$WORK/systemd"
  curl -fsSL "$REPO_RAW/systemd/tailscaled.service"          -o "$WORK/systemd/tailscaled.service"
  curl -fsSL "$REPO_RAW/systemd/tailscaled-watchdog.service" -o "$WORK/systemd/tailscaled-watchdog.service"
  curl -fsSL "$REPO_RAW/systemd/tailscaled-watchdog.timer"   -o "$WORK/systemd/tailscaled-watchdog.timer"
  chmod +x "$WORK/build.sh"
  ( cd "$WORK" && TAILSCALE_VERSION="$TAILSCALE_VERSION" ARCH="$ARCH" ./build.sh )
  RAW="$WORK/tailscale.raw"
  UNIT_SRC="$WORK/systemd"
fi
[[ -s "$RAW" ]] || { echo "✗ build failed — no .raw produced" >&2; exit 1; }
for u in tailscaled-watchdog.service tailscaled-watchdog.timer; do
  [[ -s "$UNIT_SRC/$u" ]] || { echo "✗ missing watchdog unit: $UNIT_SRC/$u" >&2; exit 1; }
done

# ── Deploy ───────────────────────────────────────────────────────────────
echo ""
echo "▶ Installing $RAW → /var/lib/extensions/tailscale.raw"
install -m 0644 "$RAW" /var/lib/extensions/tailscale.raw

echo "▶ Refreshing sysext overlay"
systemd-sysext refresh

# Boot-order watchdog — see README "Boot-order workaround".
# tailscaled.service lives *inside* the sysext; on ZimaOS multi-user.target is
# assembled before systemd-sysext.service finishes merging the overlay, so the
# in-sysext unit is missed at boot. These two units live on the persistent root
# and start tailscaled a few seconds into boot, once the overlay is merged.
echo "▶ Installing boot-order watchdog → /etc/systemd/system/"
install -m 0644 "$UNIT_SRC/tailscaled-watchdog.service" /etc/systemd/system/tailscaled-watchdog.service
install -m 0644 "$UNIT_SRC/tailscaled-watchdog.timer"   /etc/systemd/system/tailscaled-watchdog.timer

echo "▶ Enabling tailscaled.service + boot-order watchdog"
systemctl daemon-reload
systemctl enable tailscaled.service
# `restart` and not `enable --now`: on a re-install (the documented way to update)
# the unit is already active, so `--now` does nothing and the *running* daemon keeps
# executing the binary it started with — a new Tailscale version would only take
# effect at the next reboot. `restart` starts it if it is inactive and swaps it if
# it is running, at the price of a ~2 s tailnet interruption.
#
# reset-failed first: on a host affected by the boot race (tailscaled started
# before /DATA was mounted, failed five times in half a second and exhausted its
# start limit) the unit sits in failed state with its rate counter spent, and
# `restart` inside the 10s window is refused with "Start request repeated too
# quickly" — the install would abort under `set -e` on an otherwise fine system.
# No-op on a healthy unit.
systemctl reset-failed tailscaled.service 2>/dev/null || true
systemctl restart tailscaled.service
systemctl enable --now tailscaled-watchdog.timer

# ── Verify ───────────────────────────────────────────────────────────────
sleep 2
echo ""
echo "═══ Status ═══"
systemctl --no-pager status tailscaled.service | sed -n '1,8p' || true
echo ""

TS_JSON="$(/usr/bin/tailscale status --json 2>/dev/null || true)"
if grep -q '"BackendState": *"NeedsLogin"' <<<"$TS_JSON"; then
  echo ""
  echo "▶ Tailscale is installed but not yet authenticated. Next step:"
  echo ""
  echo "    sudo tailscale up"
  echo ""
  echo "  (then open the printed login URL in your browser)"
elif /usr/bin/tailscale status >/dev/null 2>&1; then
  echo "✓ Tailscale is up and connected:"
  # `sed -n 1,5p` and not `head -5`: head exits after 5 lines, `tailscale status`
  # dies of SIGPIPE, and `set -o pipefail` then aborts the installer with exit 141
  # right before the final message — a successful install reporting failure.
  /usr/bin/tailscale status | sed -n '1,5p'
else
  echo "⚠ tailscaled started but status check inconclusive — see 'journalctl -u tailscaled' for details"
fi

echo ""
echo "Done. State persists at /DATA/AppData/tailscale/."
