# Changelog

## v1.0.0 — 2026-05-08

Initial release.

- Builds `tailscale.raw` from upstream Tailscale static tarball (no cross-compile required)
- Install layout matches Buildroot `package/tailscale/tailscale.mk` 1:1 (binary in `/usr/bin/tailscaled`, symlink in `/usr/sbin`, unit in `/usr/lib/systemd/system/`)
- Adapted systemd unit: state at `/DATA/AppData/tailscale/` (ZimaOS `/var/` is tmpfs), `EnvironmentFile` made optional
- gzip squashfs (ZimaOS kernel has no `SQUASHFS_ZSTD`)
- Verified on ZimaOS v1.6.1 / kernel 6.12.25 / ZimaCube
- Includes `install.sh`, `uninstall.sh`, Mod-Store submission template
