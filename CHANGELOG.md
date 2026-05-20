# Changelog

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
