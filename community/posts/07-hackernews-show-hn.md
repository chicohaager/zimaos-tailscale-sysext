# Show HN: Tailscale as a systemd-sysext for ZimaOS (no Docker, mirrors Buildroot recipe)

**Title (≤ 80 chars):**
```
Show HN: Native Tailscale on ZimaOS via systemd-sysext, no Docker
```

**URL:** `https://github.com/<DEIN-USER>/zimaos-tailscale-sysext`

**First comment (post yourself, give context — HN convention):**

ZimaOS is a Buildroot-based NAS OS with read-only root and no package manager. The official path for native packages is `systemd-sysext` (SquashFS overlay onto /usr at runtime).

I packaged Tailscale as such an extension, mirroring the upstream Buildroot recipe `package/tailscale/tailscale.mk` exactly — same install paths, same systemd unit shape — only the state directory had to move to /DATA/ since /var/ is tmpfs on ZimaOS.

The repo also contains a drop-in kernel-config request for IceWhale: `CONFIG_IPV6_MULTIPLE_TABLES` and three related flags are not currently enabled in their kernel build, which makes Tailscale auto-disable IPv6 tunneling. IPv4 mesh works fully today.

Happy to answer questions about the sysext mechanism — it's underused in the homelab/NAS space and works great as a buildroot-package equivalent for closed-source Buildroot distros.

---

**Timing recommendation:** post Tuesday–Thursday 7–9 AM PT for highest visibility. Don't post if Steps 1–3 (Mod-Store + ZimaOS Forum + Discord) haven't surfaced any feedback yet — HN is brutal on stale Show-HNs with no engagement signals.
