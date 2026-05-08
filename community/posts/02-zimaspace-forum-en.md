# Tailscale running natively on ZimaOS — sharing a sysext module

Hey folks,

I've been running ZimaOS on a ZimaCube for a while as my main homelab box, and one thing that always bugged me was getting Tailscale onto it cleanly. The Docker container works, but it runs with `--tun=userspace-networking`, which means no real subnet-router and a slightly weird networking story. I wanted Tailscale to feel like a first-class citizen on the host the same way it does on a regular Linux server — `systemctl status tailscaled` and done.

Since ZimaOS has a read-only root and no package manager, the obvious "just `apt install`" path isn't there. But I noticed ZimaOS is Buildroot-based, and Buildroot already has an [official Tailscale recipe](https://github.com/buildroot/buildroot/blob/master/package/tailscale/tailscale.mk) — it builds the daemon, drops it into `/usr/bin`, installs the systemd unit, etc. The natural Buildroot equivalent that doesn't require rebuilding the whole ZimaOS image is `systemd-sysext`, which is what ZimaOS uses for its own modules anyway (cron, casadrop, web-ftp-client, …). Third-party sysexts are accepted in the Mod-Store too.

So I packaged Tailscale exactly the same way the upstream Buildroot recipe does — same paths, same symlinks, same systemd unit shape — but as a runtime sysext extension instead of a kernel-image change. State goes under `/DATA/AppData/tailscale/` (because `/var/` is tmpfs on ZimaOS, otherwise you'd lose your auth on every reboot). One file gets dropped into `/var/lib/extensions/`, `systemd-sysext refresh`, and you're done.

Repo: <https://github.com/chicohaager/zimaos-tailscale-sysext>

Quick install on the host:

```bash
git clone https://github.com/chicohaager/zimaos-tailscale-sysext
cd zimaos-tailscale-sysext
sudo ./install.sh
sudo tailscale up
```

A few things worth mentioning upfront:

- **It survives reboots and ZimaOS updates.** `/var/lib/extensions/` is a bind-mount onto the ext4 partition on ZimaOS (despite the `/var` prefix, which threw me at first), and `systemd-sysext.service` re-merges the extension at boot. After a ZimaOS upgrade, just re-run `install.sh` and your auth state is still there.
- **The installer rebuilds the `.raw` from the official Tailscale static tarball** (`pkgs.tailscale.com`) and verifies the SHA256 against Tailscale's own published hash. No mystery binaries.
- **One real limitation, fully honest:** the ZimaOS kernel image doesn't enable `CONFIG_IPV6_MULTIPLE_TABLES` (and a few related flags). Tailscale notices this at startup and auto-disables IPv6 tunneling — IPv4 mesh, subnet-router and exit-node all work fine, but IPv6-over-tailnet doesn't. There's nothing a userspace module can do about that; the kernel has to be rebuilt by IceWhale. I've drafted a feature-request body in the repo (`mod-store/ICEWHALE_KERNEL_REQUEST.md`) — if a few of you upvote it once it's filed, that helps prioritize a fix.

There's also a Mod-Store PR open in parallel — once that gets merged, this becomes a regular 1-click install in the ZimaOS UI alongside the other community modules. (For context: I also maintain the [`chicohaager/cron`](https://github.com/chicohaager/cron) module that's already in the Mod-Store, so this is the same delivery mechanism.)

Verified working on ZimaOS v1.6.1 / kernel 6.12.25 / ZimaCube. Should be fine on ZimaCube Pro too, and on ZimaBoard if you set `ARCH=arm64` (haven't tested ARM myself yet — would love confirmation if anyone has one).

Anyway — figured I'd share in case anyone else has wanted real Tailscale on the host without the Docker workaround. Happy to answer questions or take feedback (here or via GitHub issues), and if anyone runs into something the installer doesn't handle gracefully, please tell me.

Holger / chicohaager
