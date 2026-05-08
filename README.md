# zimaos-tailscale-sysext

**Tailscale as a native `systemd-sysext` extension for ZimaOS.** No Docker container — the Tailscale daemon runs directly on the host with real TUN, full subnet-router/exit-node support, and boot persistence.

---

## What this is (and why)

ZimaOS is a Buildroot-based NAS OS with a **read-only root filesystem** and no package manager. The ZimaOS source isn't public, so submitting a Buildroot package upstream isn't really an option.

The clean native-extension mechanism on ZimaOS is **`systemd-sysext`** — a SquashFS overlay onto `/usr` at runtime. ZimaOS itself uses it (e.g. `cron.raw`, `casadrop.raw`, `xpkg.raw`), and third-party modules are allowed.

This repo packages Tailscale as such an extension. The install layout matches the **upstream Buildroot recipe** [`package/tailscale/tailscale.mk`](https://github.com/buildroot/buildroot/blob/master/package/tailscale/tailscale.mk) one-to-one:

| | Buildroot `tailscale.mk` | this sysext |
|---|---|---|
| `/usr/bin/tailscaled` | binary | binary (from upstream static tarball) |
| `/usr/sbin/tailscaled` | symlink → `../bin/tailscaled` | identical |
| `/usr/bin/tailscale` | CLI | CLI |
| `/usr/lib/systemd/system/tailscaled.service` | unit | unit (adapted, see below) |
| state | `/var/lib/tailscale` (StateDirectory) | `/DATA/AppData/tailscale/` (ZimaOS-specific) |
| build | cross-compile via Buildroot Go | upstream static binary |

Verified on **ZimaOS v1.6.1, kernel 6.12.25, ZimaCube** (2026-05-08).

---

## Requirements

- ZimaOS x86_64 (for ARM boards set `ARCH=arm64`)
- Kernel has `TUN`, `NF_TABLES`, `NF_NAT`, `NF_CONNTRACK`, `NETFILTER` (all present on v1.6.1)
- root / sudo access for `/var/lib/extensions/`
- internet access for the Tailscale tarball

> ### ⚠ Known IPv6 limitation (ZimaOS kernel issue, not this module)
>
> ZimaOS's kernel image has a handful of `CONFIG_*` flags disabled that Tailscale needs for full IPv6 functionality. **Sysext cannot fix this** — these flags have to be set in the kernel before it is compiled.
>
> **Concrete effect:** Tailscale auto-disables tunneled IPv6 and logs:
>
> ```
> router: disabling tunneled IPv6 due to system IPv6 config:
>   kernel doesn't support IPv6 policy routing
> ```
>
> Mesh VPN over IPv4, IPv4 subnet-router and IPv4 exit-node work **without any restriction**. Only IPv6 connectivity inside the tailnet is off.
>
> **Audit on ZimaOS v1.6.1 / kernel 6.12.25:**
>
> | Config | Status | Effect when missing |
> |---|---|---|
> | `CONFIG_IPV6_MULTIPLE_TABLES` | ❌ not set | 🔴 IPv6 tunneling disabled entirely |
> | `CONFIG_IPV6_SUBTREES` | ❌ not present | 🟡 no source-prefix routes |
> | `CONFIG_NETFILTER_XT_TARGET_MARK` | ❌ not set | 🟡 no iptables `-j MARK` |
> | `CONFIG_IP6_NF_TARGET_MASQUERADE` | ❌ not set | 🟡 no IPv6 subnet-router masquerading |
> | `CONFIG_IP_MULTIPLE_TABLES`, `CONFIG_NETFILTER_XT_MARK`, `CONFIG_NETFILTER_XT_MATCH_MARK`, `CONFIG_IP6_NF_IPTABLES/FILTER/MANGLE` | ✅ enabled | – |
>
> **What you can do:** File the kernel config request with IceWhale — template under [`mod-store/ICEWHALE_KERNEL_REQUEST.md`](mod-store/ICEWHALE_KERNEL_REQUEST.md). The more 👍 the issue gets, the better the odds.

---

## Quick install

```bash
# On the ZimaOS host as root (or with sudo):
sudo ./install.sh
sudo tailscale up
```

The installer

1. sanity-checks the host,
2. downloads the official Tailscale static tarball from `pkgs.tailscale.com`,
3. builds `tailscale.raw` (gzip-squashfs, ~35 MB),
4. installs to `/var/lib/extensions/`,
5. enables `tailscaled.service`.

### Via curl (once the repo is public)

```bash
curl -fsSL https://raw.githubusercontent.com/<YOU>/zimaos-tailscale-sysext/main/install.sh \
  | sudo REPO_RAW=https://raw.githubusercontent.com/<YOU>/zimaos-tailscale-sysext/main bash
```

---

## Manual install

```bash
./build.sh                            # latest stable
TAILSCALE_VERSION=1.96.4 ./build.sh   # pinned

scp tailscale.raw root@zimaos:/tmp/

# on the host:
sudo cp /tmp/tailscale.raw /var/lib/extensions/
sudo systemd-sysext refresh
sudo systemctl daemon-reload
sudo systemctl enable --now tailscaled
sudo tailscale up
```

---

## Configuration

### Subnet router

```bash
sudo tailscale up --advertise-routes=192.168.1.0/24 --accept-routes
```

Approve the routes in the Tailscale admin console.

### Exit node

```bash
sudo tailscale up --advertise-exit-node
```

### Service flags

`/etc/default/tailscaled` is read optionally:

```bash
PORT="41641"
FLAGS="--advertise-routes=192.168.1.0/24 --accept-routes"
```

Then `sudo systemctl restart tailscaled`.

### IP forwarding

```bash
echo 'net.ipv4.ip_forward = 1'   | sudo tee -a /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo sysctl --system
```

---

## Persistence & updates

- `/var/lib/extensions/tailscale.raw` is persistent despite the `/var` prefix — it's a bind-mount from `/var/lib/casaos_data/.extensions/` on the ext4 partition.
- Auth state lives under `/DATA/AppData/tailscale/`.
- After a ZimaOS upgrade just re-run `install.sh` (or rebuild and copy the `.raw`). Auth state survives.
- After reboot `systemd-sysext.service` re-merges the extension, `tailscaled.service` starts automatically.

---

## Uninstall

```bash
sudo ./uninstall.sh            # remove sysext, keep state
sudo ./uninstall.sh --purge    # also wipe /DATA/AppData/tailscale/
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `systemd-sysext refresh` → `Invalid argument` | `.raw` compressed with zstd (kernel has no SQUASHFS_ZSTD) | use `mksquashfs … -comp gzip` (build.sh does this) |
| `tailscaled.service inactive`, but Tailscale appears to be running | Parallel `tailscale/tailscale` Docker container | `docker stop tailscale && docker update --restart=no tailscale` |
| Service starts, `BackendState=NeedsLogin` | normal after first install | `sudo tailscale up` |
| Subnet-router routes don't work | IP forwarding not enabled | see "IP forwarding" above |

Logs:

```bash
sudo journalctl -u tailscaled -f
sudo tailscale netcheck
```

---

## License

MIT (see [LICENSE](LICENSE)). Tailscale binaries are BSD-3-Clause; see [NOTICE](NOTICE).

---

## Related

- Buildroot recipe: [package/tailscale/tailscale.mk](https://github.com/buildroot/buildroot/blob/master/package/tailscale/tailscale.mk)
- Existing ZimaOS third-party sysext: [chicohaager/cron](https://github.com/chicohaager/cron)
- ZimaOS Mod-Store: [IceWhaleTech/Mod-Store](https://github.com/IceWhaleTech/Mod-Store)
