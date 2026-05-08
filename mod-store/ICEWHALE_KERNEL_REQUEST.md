# [Kernel Config Request] Enable IPv6 policy routing & netfilter MARK target for native VPN support

## Summary

Please enable a small set of additional `CONFIG_*` flags in the ZimaOS kernel build so that native VPN clients (Tailscale, WireGuard userspace tooling, …) can run with full IPv6 support and proper firewall mark handling. This affects anyone running Tailscale natively on the host — IPv6 inside the tailnet is currently **disabled at runtime by Tailscale itself**.

## Reproduction

ZimaOS v1.6.1 (any), kernel 6.12.25, ZimaCube. Install the upstream Tailscale daemon (e.g. via the [zimaos-tailscale-sysext](https://github.com/CHANGE-ME/zimaos-tailscale-sysext) module or any direct install) and run `tailscale up`. `journalctl -u tailscaled` shows:

```
router: disabling tunneled IPv6 due to system IPv6 config:
  kernel doesn't support IPv6 policy routing:
  querying IPv6 policy routing rules: address family not supported by protocol
```

`tailscale debug netcheck` confirms `ipv6=false, ipv6os=true` — the host has IPv6, but Tailscale refuses to use it because the kernel cannot do IPv6 policy routing.

## Audit of current ZimaOS kernel config

Verified on ZimaOS v1.6.1 / kernel 6.12.25 (`zcat /proc/config.gz`):

| Flag | Current | Requested | Why |
|------|---------|-----------|-----|
| `CONFIG_IPV6_MULTIPLE_TABLES` | not set | **`=y`** | **Hard requirement** — Tailscale (and any policy-routing VPN) needs multiple IPv6 routing tables. Without it, IPv6 tunneling is disabled. |
| `CONFIG_IPV6_SUBTREES` | not present | **`=y`** | Source-prefix-specific IPv6 routes (`ip -6 rule from <prefix>`). Used by Tailscale and modern systemd-networkd setups. |
| `CONFIG_NETFILTER_XT_TARGET_MARK` | not set | **`=y`** or `=m` | Allows `iptables -j MARK` — used by VPN clients to tag tunneled packets. Tailscale currently falls back to `firewallmode="ipt-default"` instead of the preferred mark-based mode. |
| `CONFIG_IP6_NF_TARGET_MASQUERADE` | not set | **`=y`** or `=m` | Required for IPv6 subnet-router masquerading. |

**Already enabled** (no change needed): `CONFIG_IP_MULTIPLE_TABLES`, `CONFIG_NETFILTER_XT_MARK`, `CONFIG_NETFILTER_XT_MATCH_MARK`, `CONFIG_IP6_NF_IPTABLES`, `CONFIG_IP6_NF_FILTER`, `CONFIG_IP6_NF_MANGLE`, `CONFIG_NF_NAT_MASQUERADE`, `CONFIG_IP6_NF_NAT`, `CONFIG_NF_DEFRAG_IPV6`.

## Why this matters

- ZimaOS users who run Tailscale natively (a common request — see [issue/forum-thread]) lose IPv6-over-VPN entirely.
- IPv6-only DERP relays don't work, falling back to slower IPv4 paths.
- CI/CD setups that connect from IPv6-only networks break, because Tailscale can't establish IPv6 endpoints from the ZimaOS side.
- Buildroot's own [`package/tailscale/tailscale.mk`](https://github.com/buildroot/buildroot/blob/master/package/tailscale/tailscale.mk) already calls out `CONFIG_IPV6_MULTIPLE_TABLES` as part of the `LINUX_CONFIG_FIXUPS` for the Tailscale package — this is the upstream-recommended kernel config for Tailscale on Buildroot.

## Suggested patch

In the ZimaOS Buildroot kernel fragment (or `linux.config`):

```
CONFIG_IPV6_MULTIPLE_TABLES=y
CONFIG_IPV6_SUBTREES=y
CONFIG_NETFILTER_XT_TARGET_MARK=m
CONFIG_IP6_NF_TARGET_MASQUERADE=m
```

(`=m` is fine for the netfilter targets — they're auto-loaded by iptables/nft on demand. `IPV6_MULTIPLE_TABLES` and `IPV6_SUBTREES` need `=y` because they're built into the IPv6 stack.)

This is a minimal, low-risk change — no userland ABI impact, no surface for new bugs in the default ZimaOS path. Affected users gain full IPv6 VPN support; everyone else is unaffected.

## Related

- Buildroot recipe: <https://github.com/buildroot/buildroot/blob/master/package/tailscale/tailscale.mk>
- Tailscale documentation on Linux requirements: <https://tailscale.com/kb/1019/install-linux>
- Community sysext module: <https://github.com/CHANGE-ME/zimaos-tailscale-sysext>

Thanks for considering 🙏
