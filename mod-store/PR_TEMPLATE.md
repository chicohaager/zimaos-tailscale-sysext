# Add `tailscale` to Mod-Store

## Summary

Adds [Tailscale](https://tailscale.com) as a community sysext module for ZimaOS.

Tailscale is a zero-config mesh VPN built on WireGuard. This module installs the official `tailscaled` daemon natively (real TUN, no Docker container), so subnet-router and exit-node features work properly. The state is persisted under `/DATA/AppData/tailscale/`.

## Module details

- **Name:** `tailscale`
- **Source repo:** https://github.com/<CHANGE-ME>/zimaos-tailscale-sysext
- **License:** MIT (build/packaging) + BSD-3-Clause (upstream Tailscale)
- **Architectures:** amd64 (arm64 supported via build flag)
- **Verified on:** ZimaOS v1.6.1 / kernel 6.12.25 / ZimaCube (2026-05-08)

## Install layout

Mirrors the Buildroot `package/tailscale/tailscale.mk` recipe. State directory adapted to `/DATA/` because `/var/` on ZimaOS is tmpfs.

## Mod-Store entry (proposed addition to `mod-v2.json`)

```json
{
  "name": "tailscale",
  "title": "Tailscale",
  "repo": "<CHANGE-ME>/zimaos-tailscale-sysext"
}
```

## Tested

- Fresh install → `tailscale up` → mesh VPN connectivity ✓
- Reboot → automatic re-load via `systemd-sysext.service` ✓
- Uninstall (sysext + service) ✓
- Reinstall preserves auth state ✓
