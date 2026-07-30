# Changelog

## v1.0.2 — 2026-07-30

IPv6 inside the tailnet now works — the ZimaOS kernel caught up.

- **Kernel 6.18.9** (ZimaOS v1.6.2-beta2 and later, including stable **v1.7.0**) enables `CONFIG_IPV6_MULTIPLE_TABLES=y`, `CONFIG_IPV6_SUBTREES=y` and `CONFIG_NETFILTER_XT_TARGET_MARK=m` — the flags that were missing on v1.6.1 / kernel 6.12.25. `tailscaled` no longer logs `router: disabling tunneled IPv6 …`; it reports `netfilter running in iptables mode v6 = true, v6filter = true, v6nat = true` and the node gets its `fd7a:115c:a1e0::…` address. Verified with real traffic (`curl -6` → HTTP 200 from two tailnet peers, SSH banner over a raw IPv6 TCP connection) on a ZimaCube with Tailscale 1.98.10.
- **IPv6 masquerading verified functionally** (2026-07-30, as root on the same host): adding `ip6tables -t nat -A POSTROUTING … -j MASQUERADE` succeeds on all three front-ends (`ip6tables` — nft-backed by default here —, `ip6tables-legacy`, `ip6tables-nft`), confirmed with `-C` and removed afterwards, while a bogus target is rejected (rc=2) — so the success is a real verdict. `tailscaled` itself already carries `-A ts-postrouting -m mark --mark 0x40000/0xff0000 -j MASQUERADE` in the live ip6tables `nat` table. `lsmod` is empty of `xt_MASQUERADE` because the target is built in (`=y`), not a module.
- `install.sh`: the IPv6 capability audit no longer raises a false alarm for `CONFIG_IP6_NF_TARGET_MASQUERADE`. Since Linux 5.2 that symbol is a pure backwards-compat alias that selects `CONFIG_NETFILTER_XT_TARGET_MASQUERADE` (`net/ipv6/netfilter/Kconfig`); the audit now accepts either name. It also prints a positive line when the kernel is complete, and points at a ZimaOS upgrade instead of asking users to file the (now resolved) kernel feature request.
- README / HOWTO: the "Known IPv6 limitation" warning became a "works as of v1.7.0" section with the per-version config audit, plus two troubleshooting rows — one for the old `disabling tunneled IPv6` log line, one for `tailscale netcheck` reporting `IPv6: no, but OS has support`, which is about the ISP/LAN having no global IPv6 and *not* about the kernel.
- `mod-store/ICEWHALE_KERNEL_REQUEST.md` marked resolved (kept for the record).

Installer fixes found while running the documented install end-to-end on a v1.7.0 host:

- **The conflict prompt broke the piped install.** `read -r -p … ans` read from stdin, but in `curl … | sudo bash` stdin *is* the script — the line after the `read` got swallowed as the answer and never ran (that line was the abort check itself). Now it prompts on stdin when that is a terminal, else on `/dev/tty`, and if there is no terminal at all it says so and continues.
- **A successful install exited 141.** `tailscale status | head -5` under `set -o pipefail`: head exits after five lines, `tailscale status` dies of SIGPIPE, and the installer aborted right before its final message — only on the "already connected" path, i.e. exactly when re-installing to update. Same race fixed in three more places where it could only ever fail silently: the docker-conflict check (would have left a conflicting container running), the `NeedsLogin` check (would have claimed "up and connected"), the `CONFIG_SQUASHFS_ZLIB` check (would have warned about a flag that is present), and `build.sh`'s version resolver (`| head -1` mid-pipeline could abort the build with no message).
- **A re-install did not activate the new binary.** `systemctl enable --now tailscaled` does nothing to an already-running unit, so the old daemon process kept running and a Tailscale upgrade would only have taken effect at the next reboot. Now `systemctl restart` (starts it when inactive, swaps it when running, ~2 s tailnet interruption).
- **Boot persistence re-verified on v1.7.0** with an actual reboot: sysext merged at 08:19:24, the watchdog fired at 08:19:32 and started `tailscaled` (active 08:19:34) — systemd never scheduled the in-sysext unit itself, so the watchdog is still required. Tailnet IPv6 carried real traffic again immediately after, and all 27 containers on the host came back.
- Note: ZimaOS v1.7.0 also ships `CONFIG_SQUASHFS_ZSTD=y`, but `build.sh` stays on gzip so one `.raw` keeps working on v1.6.x too.

## v1.0.1 — 2026-05-20

Fix: `tailscaled` did not start after a reboot.

- **Root cause:** ZimaOS resolves `multi-user.target`'s `WantedBy=` symlinks before `systemd-sysext.service` finishes merging the overlay, so `tailscaled.service` — which lives inside `tailscale.raw` — is invisible at that moment and is never scheduled. The daemon stayed `inactive (dead)` after every boot, with no log line and no error.
- **Fix:** added `tailscaled-watchdog.service` + `tailscaled-watchdog.timer`, installed into `/etc/systemd/system/` (persistent root, present from early boot). The timer fires ~15 s into boot and starts `tailscaled` once the overlay is merged. Modeled on the `cron.raw` workaround (`chicohaager/cron`).
- `install.sh` now deploys and enables the watchdog; `uninstall.sh` removes it.
- README: corrected the "starts automatically after reboot" claim, added a "Boot-order workaround" section and a troubleshooting row.

Also in this release:

- `install.sh`: fixed a dead conflict check — `pgrep -f '…\|…'` never matched a running daemon (`\|` is a literal pipe in `pgrep`'s ERE, not alternation); now `pgrep -x tailscaled`.
- `build.sh`: resolve the Tailscale version from the `pkgs.tailscale.com/stable` manifest (the actual download source) instead of the GitHub releases API — removes channel skew, the 60 req/h API rate limit, and a `grep '\s'` GNU-ism busybox grep may not support.
- `tailscaled.service`: added `ExecStartPre=-/usr/sbin/tailscaled --cleanup` to clear stale interface/firewall state left by an unclean shutdown (matches the upstream unit).

## v1.0.0 — 2026-05-08

Initial release.

- Builds `tailscale.raw` from upstream Tailscale static tarball (no cross-compile required)
- Install layout matches Buildroot `package/tailscale/tailscale.mk` 1:1 (binary in `/usr/bin/tailscaled`, symlink in `/usr/sbin`, unit in `/usr/lib/systemd/system/`)
- Adapted systemd unit: state at `/DATA/AppData/tailscale/` (ZimaOS `/var/` is tmpfs), `EnvironmentFile` made optional
- gzip squashfs (ZimaOS kernel has no `SQUASHFS_ZSTD`)
- Verified on ZimaOS v1.6.1 / kernel 6.12.25 / ZimaCube
- Includes `install.sh`, `uninstall.sh`, Mod-Store submission template
