# Add Tailscale community sysext module

## What

[Tailscale](https://tailscale.com) — a zero-config WireGuard-based mesh VPN — packaged as a community `systemd-sysext` module for ZimaOS.

## Why a module instead of just a Docker container

Running Tailscale as a Docker container on ZimaOS is possible but inherits the userspace-networking limitation: no real TUN, subnet-router and exit-node features are degraded. A native module gives users the full feature set with no extra config.

The install layout follows the upstream Buildroot recipe [`package/tailscale/tailscale.mk`](https://github.com/buildroot/buildroot/blob/master/package/tailscale/tailscale.mk) one-to-one (paths, symlinks, systemd unit), which means it's the same shape Tailscale would have if ZimaOS had built it as a Buildroot package directly.

## Module entry to add to `mod-v2.json`

```json
{
  "name": "tailscale",
  "title": "Tailscale",
  "repo": "<DEIN-USER>/zimaos-tailscale-sysext"
}
```

## Tested

- Fresh install on ZimaOS v1.6.1 / kernel 6.12.25 / ZimaCube → connectivity ✓
- Reboot → automatic re-load via `systemd-sysext.service` ✓
- Uninstall + reinstall preserves auth state under `/DATA/AppData/tailscale/` ✓
- Coexistence: stops any pre-existing `tailscale/tailscale` Docker container automatically (without removing its volume) ✓

## License & attribution

- MIT for build/packaging
- Tailscale binaries: BSD-3-Clause (Tailscale Inc.) — see `NOTICE`
- Inspired directly by the Buildroot recipe (also referenced in `NOTICE`)

## Side note for the kernel team

A small set of kernel `CONFIG_*` flags is currently missing for full IPv6 Tailscale functionality. I've documented this in [`mod-store/ICEWHALE_KERNEL_REQUEST.md`](https://github.com/<DEIN-USER>/zimaos-tailscale-sysext/blob/main/mod-store/ICEWHALE_KERNEL_REQUEST.md) — happy to file it as a separate issue against the ZimaOS repo once this PR is in. Doesn't block this module — IPv4 works fully today.

Thanks for considering 🙏
