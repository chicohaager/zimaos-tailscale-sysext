# [Module] Native Tailscale on ZimaOS — as a systemd-sysext

Hi all,

I packaged Tailscale as a native `systemd-sysext` module for ZimaOS. If you've been running Tailscale in a Docker container and ran into the usual limitations (`--tun=userspace-networking`, no real subnet-router, awkward exit-node) — this runs directly on the host as a regular systemd service with proper TUN.

**Repo:** <https://github.com/<DEIN-USER>/zimaos-tailscale-sysext>

## What's in the box

- `build.sh` — reproducibly builds a `tailscale.raw` from the official Tailscale static tarball
- `install.sh` — one-shot installer on the ZimaOS host (sanity-check → build → deploy → enable service)
- `uninstall.sh` — clean removal, optionally preserves auth state under `/DATA/AppData/tailscale/`
- README in DE+EN, MIT license, Mod-Store submission template

Layout matches the upstream Buildroot recipe `package/tailscale/tailscale.mk` 1:1 — `tailscaled` in `/usr/bin/`, symlink in `/usr/sbin/`, unit in `/usr/lib/systemd/system/`. The only ZimaOS-specific tweak: state lives under `/DATA/AppData/tailscale/` instead of `/var/lib/tailscale/`, because `/var/` is tmpfs on ZimaOS.

## Quick install

```bash
git clone https://github.com/<DEIN-USER>/zimaos-tailscale-sysext
cd zimaos-tailscale-sysext
sudo ./install.sh
sudo tailscale up
```

Then open the printed login URL in your browser — done. Survives reboot automatically (`/var/lib/extensions/` is a bind-mount onto ext4 on ZimaOS, not tmpfs — `systemd-sysext.service` re-loads it at boot).

## Verified

ZimaOS v1.6.1 / kernel 6.12.25 / ZimaCube, Tailscale 1.96.4.

## Known limitation: IPv6

ZimaOS's kernel currently does not enable `CONFIG_IPV6_MULTIPLE_TABLES` (and a few related flags). Tailscale logs `disabling tunneled IPv6 due to system IPv6 config` at startup and turns IPv6 tunneling off. **IPv4 mesh, subnet-router and exit-node work without any restriction.** A drop-in bug report for IceWhale is in the repo at `mod-store/ICEWHALE_KERNEL_REQUEST.md` — if you 👍 the issue once it's filed, it improves the odds of a kernel fix in a future ZimaOS release.

## Mod-Store PR

I've also opened a PR against `IceWhaleTech/Mod-Store` so the module shows up as a 1-click install in the ZimaOS UI once merged. After that, no git/build needed.

Feedback and bug reports welcome — GitHub issues or this thread.

— Holger
