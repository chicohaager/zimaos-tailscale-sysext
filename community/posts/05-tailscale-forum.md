# [Showcase] Native Tailscale on ZimaOS as a systemd-sysext extension

ZimaOS (Buildroot-based NAS OS by IceWhaleTech) has a read-only root and no package manager, which makes a clean Tailscale install non-trivial. The Docker container path works but loses real TUN.

I built a `systemd-sysext` extension that follows the official Buildroot `package/tailscale/tailscale.mk` recipe layout exactly, so it's structurally what Tailscale would look like if shipped as a first-party Buildroot package — but distributed as a runtime SquashFS overlay since ZimaOS source isn't open.

**Repo:** <https://github.com/<DEIN-USER>/zimaos-tailscale-sysext>

Verified working on Tailscale 1.96.4 / ZimaOS v1.6.1 / kernel 6.12.25, with `firewallmode="ipt-default"` auto-selected. Sharing here in case the showcase is useful for others on Buildroot-based hosts where neither apt nor a writable rootfs are available.

One IPv6 caveat that might be of interest to the Tailscale team: the ZimaOS kernel doesn't enable `CONFIG_IPV6_MULTIPLE_TABLES`, which trips your `disabling tunneled IPv6 due to system IPv6 config` path. I've drafted a kernel-config request to IceWhale (also in the repo) — let me know if there's a cleaner way to detect/communicate this gracefully from the daemon side.
