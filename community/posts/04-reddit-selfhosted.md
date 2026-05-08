# [Showcase] Native Tailscale on ZimaOS via systemd-sysext (no Docker, real TUN, reboot-persistent)

**TL;DR:** ZimaOS has a read-only root and no package manager, so installing Tailscale natively is awkward. I packaged it as a `systemd-sysext` extension that mirrors the upstream Buildroot recipe 1:1 — runs as a regular systemd service on the host, full subnet-router/exit-node support, survives reboots and ZimaOS updates.

**Repo:** https://github.com/chicohaager/zimaos-tailscale-sysext

## Why not just Docker?

The `tailscale/tailscale` container on ZimaOS runs with `--tun=userspace-networking`, which means:
- no real TUN device → subnet-router/exit-node features are degraded
- packet forwarding goes through userspace → noticeable latency hit
- networking integration with the host is awkward

Native install side-steps all of that.

## How it works

`systemd-sysext` is a built-in systemd feature that overlays a SquashFS image onto `/usr` at runtime. ZimaOS uses it for its own modules (cron, casadrop, web-ftp-client, etc.) and accepts third-party ones. The repo packages Tailscale's official static binaries plus a tweaked systemd unit into a `.raw` file:

```
/usr/bin/tailscale, /usr/bin/tailscaled
/usr/sbin/tailscaled  → ../bin/tailscaled  (matches buildroot.mk)
/usr/lib/systemd/system/tailscaled.service
/usr/lib/extension-release.d/extension-release.tailscale
```

The only ZimaOS-specific tweak: state directory points at `/DATA/AppData/tailscale/` instead of `/var/lib/tailscale/`, because `/var/` is tmpfs on ZimaOS (would lose auth on every reboot).

## Reproduction

```bash
git clone https://github.com/chicohaager/zimaos-tailscale-sysext
cd zimaos-tailscale-sysext
sudo ./install.sh
sudo tailscale up
```

Installer is idempotent, sanity-checks the kernel modules, and prints exactly what it's doing.

## Caveat

ZimaOS's kernel image doesn't enable `CONFIG_IPV6_MULTIPLE_TABLES` (and a few related flags), so Tailscale auto-disables IPv6 tunneling at runtime. IPv4 mesh works fully. A drop-in kernel-config request for IceWhale is in the repo — needs upstream cooperation to fully fix.

## Source layout

- MIT licensed (build scripts and packaging)
- Tailscale binaries: BSD-3-Clause, downloaded fresh from `pkgs.tailscale.com` at build time
- README in EN+DE, troubleshooting tables, full audit of which kernel configs are present/missing

Happy to answer questions or take feedback.
