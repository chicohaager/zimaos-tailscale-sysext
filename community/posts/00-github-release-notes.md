# Tailscale 1.96.4 — native systemd-sysext for ZimaOS

First release of `zimaos-tailscale-sysext`: a native Tailscale install for ZimaOS that doesn't require Docker, runs straight on the host with real TUN, and survives reboots and ZimaOS updates.

## Highlights

- **No Docker.** `tailscaled` runs as a regular `systemd` service on the host, with full subnet-router and exit-node support.
- **Buildroot-aligned layout.** Mirrors the upstream Buildroot recipe `package/tailscale/tailscale.mk` 1:1 (paths, symlinks, unit), adapted only where ZimaOS specifics demand it (state directory under `/DATA/` because `/var/` is tmpfs).
- **One command install.** `sudo ./install.sh` does everything — sanity-checks, build, deploy, enable.
- **Reproducible build.** `build.sh` packs the official Tailscale static tarball into a gzip squashfs (`-comp gzip` is required — ZimaOS kernel has no `SQUASHFS_ZSTD`).

## Verified on

- ZimaOS v1.6.1, kernel 6.12.25, ZimaCube (x86_64)
- Tailscale 1.96.4 from `pkgs.tailscale.com/stable/`

## Known limitation: IPv6

ZimaOS's kernel does **not** enable `CONFIG_IPV6_MULTIPLE_TABLES` (and a few related flags). Tailscale auto-disables IPv6 tunneling at runtime as a result. **IPv4 mesh, subnet-router and exit-node work without restriction.** A ready-to-file kernel-config request for IceWhale is included at [`mod-store/ICEWHALE_KERNEL_REQUEST.md`](https://github.com/<DEIN-USER>/zimaos-tailscale-sysext/blob/main/mod-store/ICEWHALE_KERNEL_REQUEST.md).

## Asset

- `tailscale.raw` — gzip-squashfs sysext extension, ~35 MB, x86_64
  - SHA256: `f3b5f7340372d1e1a3d15fcb2a78ef2518cc99a02565ba5e8e8b95e6ce73134e` *(rebuild may yield a different hash because squashfs encodes mtime — content layout is deterministic, see `unsquashfs -ll`)*

## Quick install

```bash
git clone https://github.com/<DEIN-USER>/zimaos-tailscale-sysext
cd zimaos-tailscale-sysext
sudo ./install.sh
sudo tailscale up
```

## License

MIT for build/packaging scripts. Bundled Tailscale binaries are BSD-3-Clause (Tailscale Inc.).
