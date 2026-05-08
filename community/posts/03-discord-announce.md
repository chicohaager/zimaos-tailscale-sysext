**Tailscale natively on ZimaOS — community sysext module 🚀**

Just released a `systemd-sysext` module that runs Tailscale directly on the ZimaOS host (no Docker, real TUN, full subnet-router/exit-node support).

📦 **Repo:** <https://github.com/chicohaager/zimaos-tailscale-sysext>
✅ Verified on ZimaOS v1.6.1, kernel 6.12.25, ZimaCube
🔁 Reboot-persistent (loaded via `systemd-sysext.service`)
🛠 One-command install: `sudo ./install.sh && sudo tailscale up`

The install layout mirrors the upstream Buildroot recipe `package/tailscale/tailscale.mk` 1:1, so it's basically what you'd get if ZimaOS shipped Tailscale as a built-in package.

Mod-Store PR is open in parallel — once merged, this becomes a 1-click install in the ZimaOS UI.

⚠ One known limitation: ZimaOS's kernel doesn't enable `CONFIG_IPV6_MULTIPLE_TABLES`, so Tailscale auto-disables IPv6 tunneling. IPv4 works fully — there's a kernel-config request template in the repo for IceWhale if anyone wants to upvote.

Feedback welcome 🙏
