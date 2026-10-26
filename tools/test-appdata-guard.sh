#!/bin/sh
# Static checks for the folder check (lintux-modkit appdata-guard.sh, ZIMAOS-KNOWLEDGE §79.11):
# /DATA/AppData is 0777 without the sticky bit on ZimaOS 1.8, and tailscaled keeps the node's
# identity in /DATA/AppData/tailscale as root — the unit checks the folder before tailscaled starts.
#   sh tools/test-appdata-guard.sh      exit 0 = all passed
set -u
cd "$(dirname "$0")/.." || exit 2
F=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; F=$((F + 1)); }
U=systemd/tailscaled.service
G='ExecStartPre=/bin/sh /usr/libexec/tailscale/appdata-guard.sh /DATA/AppData/tailscale'
gl=$(grep -n -x -F "$G" "$U" | cut -d: -f1)
sl=$(grep -n '^ExecStart=' "$U" | cut -d: -f1)
if [ -n "$gl" ] && [ -n "$sl" ] && [ "$gl" -lt "$sl" ]; then ok "tailscaled.service checks the folder before ExecStart"; else bad "tailscaled.service: want '$G' before ExecStart="; fi
# shellcheck disable=SC2016  # the literal line of build.sh, $ROOT unexpanded
if grep -q 'sysext/appdata-guard.sh" "$ROOT/usr/libexec/tailscale/appdata-guard.sh"' build.sh; then ok "build.sh puts the guard into the image"; else bad "build.sh does not install sysext/appdata-guard.sh to /usr/libexec/tailscale"; fi
M=../lintux-modkit/sysext/appdata-guard.sh
if [ ! -f sysext/appdata-guard.sh ]; then bad "sysext/appdata-guard.sh missing"
elif [ ! -f "$M" ]; then ok "guard copy present (lintux-modkit not next to the repo, not compared)"
elif cmp -s "$M" sysext/appdata-guard.sh; then ok "sysext/appdata-guard.sh is lintux-modkit's"
else bad "sysext/appdata-guard.sh differs from $M — copy it again"; fi
[ "$F" = 0 ] && echo "✓ appdata guard: 3 checks" || echo "✗ appdata guard: $F failed"
exit "$F"
