# Short-form social posts (≤ 280 chars)

Pick the variant matching the audience.

---

## Bluesky / Mastodon (selfhost / homelab tag)

```
Just released a native Tailscale install for ZimaOS — no Docker, real TUN, reboot-persistent.

Packaged as a systemd-sysext extension that mirrors the upstream Buildroot recipe 1:1.

`sudo ./install.sh && sudo tailscale up` and you're done.

https://github.com/chicohaager/zimaos-tailscale-sysext

#selfhosted #ZimaOS #Tailscale
```

---

## X / Twitter (techy)

```
Native Tailscale on ZimaOS without Docker:

→ systemd-sysext extension (35 MB squashfs)
→ matches Buildroot tailscale.mk layout
→ survives reboots + ZimaOS updates
→ one-shot installer

Repo + drop-in IceWhale kernel-config request:
https://github.com/chicohaager/zimaos-tailscale-sysext
```

---

## Mastodon (Tailscale-Bubble)

```
For anyone running Tailscale on a Buildroot-based NAS (e.g. ZimaOS) where you can't just `apt install tailscale`:

I packaged it as a systemd-sysext overlay that follows the upstream Buildroot recipe.

No Docker, no userspace-networking limits, real subnet-router.

https://github.com/chicohaager/zimaos-tailscale-sysext
```
