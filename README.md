# zimaos-tailscale-sysext

**Tailscale as a native `systemd-sysext` extension for ZimaOS.** No Docker container — the Tailscale daemon runs directly on the host with real TUN, full subnet-router/exit-node support, and boot persistence.

> 📖 Looking for the practical walkthrough? [**HOWTO.md**](HOWTO.md) covers authentication pitfalls,
> the ZimaOS WebUI over HTTPS via `tailscale serve`, and a Taildrop auto-receiver. This README
> covers the module itself.

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

Verified on **ZimaOS v1.7.0, kernel 6.18.9, ZimaCube** with Tailscale 1.98.10 (2026-07-30) —
install run end-to-end from a clean checkout, **including a reboot**: the node came back on its
own and IPv6 inside the tailnet still carried real traffic. Originally developed and verified on
**v1.6.1, kernel 6.12.25** (2026-05-08).

---

## Requirements

- ZimaOS x86_64 (for ARM boards set `ARCH=arm64`)
- Kernel has `TUN`, `NF_TABLES`, `NF_NAT`, `NF_CONNTRACK`, `NETFILTER` (all present on v1.6.1 and v1.7.0)
- root / sudo access for `/var/lib/extensions/`
- internet access for the Tailscale tarball

> ### ✅ IPv6 inside the tailnet works — as of ZimaOS v1.7.0
>
> Up to and including **ZimaOS v1.6.1** (kernel 6.12.25) the ZimaOS kernel image lacked the `CONFIG_*`
> flags Tailscale needs for IPv6 policy routing, so `tailscaled` switched tunneled IPv6 off at startup:
>
> ```
> router: disabling tunneled IPv6 due to system IPv6 config:
>   kernel doesn't support IPv6 policy routing
> ```
>
> **The 6.18 kernel ships those flags** — first seen in v1.6.2-beta2, and in the current stable
> **v1.7.0 (kernel 6.18.9)**. What decides it is the kernel image, not the ZimaOS version number —
> check yours with `uname -r`: `6.12.25` → IPv6 off, `6.18.9` → IPv6 on (or just run `install.sh`,
> which audits the flags on your host and says so). Nothing in this module had to change — the
> limitation was always in the kernel image. Re-audited on a ZimaCube with Tailscale 1.98.10, 2026-07-30:
>
> | Config | v1.6.1 / 6.12.25 | v1.7.0 / 6.18.9 |
> |---|---|---|
> | `CONFIG_IPV6_MULTIPLE_TABLES` | ❌ not set → IPv6 tunneling off | ✅ `=y` |
> | `CONFIG_IPV6_SUBTREES` | ❌ not present | ✅ `=y` |
> | `CONFIG_NETFILTER_XT_TARGET_MARK` | ❌ not set | ✅ `=m` |
> | `CONFIG_IP6_NF_TARGET_MASQUERADE` | ❌ not set | ❌ still not set — **and it does not matter**: since Linux 5.2 it is only a backwards-compat alias that selects `CONFIG_NETFILTER_XT_TARGET_MASQUERADE` (`net/ipv6/netfilter/Kconfig`), and that one is `=y`. IPv6 masquerading was tested functionally, see below |
> | `CONFIG_IP_MULTIPLE_TABLES`, `CONFIG_NETFILTER_XT_MARK`, `CONFIG_NETFILTER_XT_MATCH_MARK`, `CONFIG_IP6_NF_IPTABLES/FILTER/MANGLE/NAT` | ✅ enabled | ✅ enabled |
>
> **Measured on v1.7.0, not inferred:**
>
> - `journalctl -u tailscaled | grep -c 'disabling tunneled'` → **0** (was the tell-tale line before)
> - `router: netfilter running in iptables mode v6 = true, v6filter = true, v6nat = true`
> - `tailscale ip -6` → `fd7a:115c:a1e0::…`, and that address is actually on `tailscale0`
> - `ip -6 rule` shows Tailscale's `fwmark 0x80000/0xff0000` rules plus its own routing table
> - real payload over IPv6, not just a status flag: `curl -6 'http://[fd7a:115c:a1e0::…]/'` → **HTTP 200**
>   from two tailnet peers, and an SSH banner over a raw IPv6 TCP connection
> - **IPv6 masquerading (subnet router) works too:** `tailscaled` has already installed
>   `-A ts-postrouting -m mark --mark 0x40000/0xff0000 -j MASQUERADE` in the live ip6tables `nat`
>   table, and adding a MASQUERADE rule by hand succeeds on all three front-ends (`ip6tables`,
>   `-legacy`, `-nft`) while a bogus target is correctly rejected. Note `lsmod` shows no
>   `xt_MASQUERADE`: the target is **built into** the kernel (`=y`), so the witness is
>   `grep MASQUERADE /proc/net/ip6_tables_targets`, not the module list.
>
> **Don't be confused by `tailscale netcheck`** reporting `IPv6: no, but OS has support`. That line is
> about the *internet* path (whether your ISP/LAN gives the box a global IPv6 address for direct
> endpoints and IPv6 DERP) — not about the kernel. Tailnet IPv6 (`fd7a::/48`) works either way; the
> encrypted packets simply travel over the IPv4 underlay.
>
> **Still on kernel 6.12.25 (v1.6.1)?** Upgrade ZimaOS — that is the whole fix; a sysext cannot
> patch a kernel image.
> The original feature request that described the gap is kept for the record under
> [`mod-store/ICEWHALE_KERNEL_REQUEST.md`](mod-store/ICEWHALE_KERNEL_REQUEST.md).

---

## Quick install

On the ZimaOS host:

```bash
cd /tmp
git clone https://github.com/chicohaager/zimaos-tailscale-sysext
cd zimaos-tailscale-sysext
sudo ./install.sh
sudo tailscale up
```

`git` ships with ZimaOS (2.53.0 on v1.7.0) and the clone is only ~400 KB — the ~35 MB
`tailscale.raw` is built on the box, not shipped in the repo. `/tmp` is a tmpfs, so the
checkout is gone after the next reboot; the installed extension is not (see
[Persistence & updates](#persistence--updates)).

The installer

1. sanity-checks the host,
2. downloads the official Tailscale static tarball from `pkgs.tailscale.com`,
3. builds `tailscale.raw` (gzip-squashfs, ~35 MB),
4. installs to `/var/lib/extensions/`,
5. enables `tailscaled.service`.

### Alternative: via curl (no checkout)

```bash
curl -fsSL https://raw.githubusercontent.com/chicohaager/zimaos-tailscale-sysext/main/install.sh \
  | sudo bash
```

`install.sh` then pulls `build.sh` and the systemd units from the repo's `main` branch
(override with `REPO_RAW=…` for a fork).

---

## Manual install

Build on your workstation, copy the artifacts over. Note that ZimaOS v1.7.0 sets
`PermitRootLogin no` (verified via `sshd -T`), so copy as your normal ZimaOS user:

```bash
./build.sh                            # latest stable
TAILSCALE_VERSION=1.96.4 ./build.sh   # pinned

scp tailscale.raw systemd/tailscaled-watchdog.* <user>@zimaos:/tmp/

# on the host:
sudo cp /tmp/tailscale.raw /var/lib/extensions/
sudo systemd-sysext refresh

# boot-order watchdog (see "Boot-order workaround" above):
sudo cp /tmp/tailscaled-watchdog.service /tmp/tailscaled-watchdog.timer /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now tailscaled
sudo systemctl enable --now tailscaled-watchdog.timer
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
- After reboot `systemd-sysext.service` re-merges the extension and the bundled `tailscaled-watchdog.timer` starts `tailscaled` — see [Boot-order workaround](#boot-order-workaround).

---

## Boot-order workaround

`tailscaled.service` ships **inside** `tailscale.raw`. On ZimaOS, `multi-user.target` resolves its `WantedBy=` symlinks *before* `systemd-sysext.service` finishes merging the overlay — so at that moment the in-sysext unit doesn't exist yet and is never scheduled. Left alone, the daemon silently stays `inactive (dead)` after every reboot, with no log line and no error.

The fix is a small watchdog installed onto the **persistent** root filesystem (`/etc/systemd/system/`, which is not part of the sysext), so it is present from early boot:

| Unit | Role |
|---|---|
| `tailscaled-watchdog.timer` | `OnBootSec=15` — fires ~15 s into boot, after the overlay is merged |
| `tailscaled-watchdog.service` | oneshot: `systemctl is-active tailscaled \|\| systemctl start tailscaled` |

`install.sh` deploys and enables both; `uninstall.sh` removes them. This mirrors the workaround ZimaOS's own `cron.raw` module uses ([`chicohaager/cron`](https://github.com/chicohaager/cron)).

**Still needed on v1.7.0** — re-verified with a real reboot on 2026-07-30, from the journal of that boot:

```
08:19:16  boot
08:19:24  systemd-sysext: Merged extensions into '/usr'
08:19:32  Starting "Start tailscaled if the sysext unit was missed at boot"   ← the watchdog
08:19:32  Starting Tailscale node agent
08:19:34  tailscaled active, Connected
```

There is no earlier attempt to start `tailscaled` in that boot: systemd never scheduled the
in-sysext unit itself, the watchdog did. Tailnet IPv6 was carrying traffic again right after
(`curl -6` → HTTP 200 from two peers), and no `disabling tunneled IPv6` line appeared.

### The second failure mode: it *does* start, and crashes into the start limit

The race above is not the only way this boot goes wrong, and on some hosts it goes the
other way — reported by a user in 2026-08, fixed in **v1.0.3**. If the sysext *is* merged
in time, systemd schedules `tailscaled.service` from `multi-user.target` right away, and
then a second race decides the outcome:

- The state directory is `/DATA/AppData/tailscale`. On ZimaOS `/DATA` is **not** an
  ordinary directory — it is a bind mount of `/var/lib/casaos_data`, provided by
  `DATA.mount` and pulled in by `casaos-bind.target`, *not* by `local-fs.target`.
- `casaos-bind.target` declares `Before=multi-user.target`. That orders it before the
  **target**, but not before the target's other `Wants=` — so `tailscaled.service` and
  `DATA.mount` are free to run concurrently.
- The root filesystem is **read-only squashfs** (`/dev/nvme0n1p5`). So when `tailscaled`
  wins that race, `ExecStartPre=/bin/mkdir -p /DATA/AppData/tailscale` cannot fall back to
  creating the directory on the root — it fails with `Read-only file system`, and the unit
  dies before the daemon is ever exec'd.
- `Restart=on-failure` retried after the default `RestartSec=100ms`, and the default start
  limit is 5 starts per 10 s. Five instant failures therefore burned the entire allowance
  in about half a second, systemd gave up with **`Start request repeated too quickly`**, and
  the unit stayed `failed (Result: exit-code)` for the rest of the boot — while a manual
  `systemctl start` minutes later succeeded, because by then `/DATA` was mounted.
- The watchdog could not save it either: a plain `systemctl start` against a unit whose rate
  counter is spent is *refused*, so the watchdog reported success while doing nothing.

Three changes fix it, all in this repo:

| Change | Where | Effect |
|---|---|---|
| `RequiresMountsFor=/DATA/AppData` | `tailscaled.service` `[Unit]` | adds `Requires=` + `After=` for `DATA.mount`, so the daemon cannot start before its state directory exists |
| `StartLimitIntervalSec=0` + `RestartSec=5` | `tailscaled.service` | a transient early-boot failure can no longer latch permanently; the unit retries every 5 s until the cause clears |
| `systemctl reset-failed` before `start` | `tailscaled-watchdog.service` | flushes a spent rate counter so the watchdog can actually recover an already-failed unit |

`RequiresMountsFor` resolving to the right mount unit was verified on the ZimaOS v1.7.0 host:
`systemd-journal-flush.service`, which declares `RequiresMountsFor=/var/log/journal`, shows
`var-log.mount` in its resolved `After=` — the same mechanism `/DATA/AppData` → `DATA.mount`
relies on.

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
| `systemd-sysext refresh` → `Invalid argument` | `.raw` compressed with zstd (kernel has no SQUASHFS_ZSTD — the case on v1.6.1; v1.7.0 does have it, but `build.sh` stays on gzip so one `.raw` works on both) | use `mksquashfs … -comp gzip` (build.sh does this) |
| `tailscaled.service` `inactive (dead)` after a reboot — no log, no error | sysext merged after `multi-user.target` was assembled (see [Boot-order workaround](#boot-order-workaround)) | the bundled watchdog handles this — make sure it is enabled: `sudo systemctl enable --now tailscaled-watchdog.timer` |
| After a reboot: `failed (Result: exit-code)`, journal shows ~5 rapid starts then `Start request repeated too quickly` — but a manual `sudo systemctl start tailscaled` later works | `tailscaled` started before `/DATA` was mounted, so `ExecStartPre`'s `mkdir` hit the read-only squashfs root and the unit died instantly; five failures in half a second exhausted the default start limit (5 per 10 s) and systemd stopped retrying. Fixed in **v1.0.3** — see [Boot-order workaround](#boot-order-workaround) | update: `git pull && sudo ./install.sh`. To confirm it was this before updating: `journalctl -b -u tailscaled \| head -40` — look for `Read-only file system` or `mkdir` failing. To recover the current boot without rebooting: `sudo systemctl reset-failed tailscaled && sudo systemctl start tailscaled` |
| `tailscaled.service inactive`, but Tailscale appears to be running | Parallel `tailscale/tailscale` Docker container | `docker stop tailscale && docker update --restart=no tailscale` |
| Service starts, `BackendState=NeedsLogin` | normal after first install | `sudo tailscale up` |
| Subnet-router routes don't work | IP forwarding not enabled | see "IP forwarding" above |
| `tailscale netcheck` → `IPv6: no, but OS has support` | no global IPv6 from your ISP/LAN — this is *not* the old kernel issue | nothing to fix on the ZimaOS side; tailnet IPv6 (`fd7a::/48`) works regardless, over the IPv4 underlay |
| `router: disabling tunneled IPv6 due to system IPv6 config` in the journal | kernel without `CONFIG_IPV6_MULTIPLE_TABLES` — i.e. 6.12.25 / ZimaOS v1.6.1 | upgrade ZimaOS to a build with kernel 6.18.9 (v1.7.0); a sysext cannot patch the kernel image |

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

---

## ☕ Support

If this project saves you time, you can buy me a coffee — it keeps the side projects going.

<!-- bmc-button -->
[![Buy Me A Coffee](https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20coffee&emoji=%E2%98%95&slug=holgi18114&button_colour=FFDD00&font_colour=000000&font_family=Cookie&outline_colour=000000&coffee_colour=ffffff)](https://buymeacoffee.com/holgi18114)

… or scan the code:

<a href="https://buymeacoffee.com/holgi18114"><img src=".github/bmc-qr.png" alt="Buy Me a Coffee QR code" width="160"></a>
