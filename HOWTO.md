# HowTo: Native Tailscale on ZimaOS — HTTPS WebUI & Taildrop Auto‑Receive

A practical, end‑to‑end walkthrough for running **Tailscale natively** on a ZimaOS
box (ZimaBoard / ZimaCube), then using it to:

1. reach the **ZimaOS WebUI over HTTPS** on your tailnet (valid Let's Encrypt cert, no `-k`), and
2. turn the box into a **Taildrop drop target** that receives files automatically.

This guide complements the module's [`README.md`](README.md) (which covers the
sysext internals and subnet‑router/exit‑node setup). Here we focus on the two
things the README doesn't, plus the **authentication pitfalls** that bite people
in practice.

> **Verified:** originally on ZimaOS **v1.6.1**, kernel **6.12.25**, x86_64, Tailscale **1.98.8**,
> on a **ZimaBoard** (and previously a ZimaCube). Every command below was run on a live box before
> publishing.
>
> Re-verified on ZimaOS **v1.7.0**, kernel **6.18.9**, Tailscale **1.98.10** (ZimaCube, 2026-07-30):
> the install in step 1 end-to-end from a clean checkout **including a reboot**, the IPv6 row in
> section 5, and the `tailscale file get` flags used by the Taildrop unit in section 4.

---

## 0. Why native instead of the Docker Tailscale?

The Docker image works, but a **sysext** runs `tailscaled` directly on the host
network stack. That gives you real `TUN`, working **subnet‑router / exit‑node**
routing, and — the reason for this guide — the host's own services (the ZimaOS
WebUI) become reachable over the tailnet without container port‑mapping gymnastics.

ZimaOS has a **read‑only root** and **no package manager**, so `systemd-sysext`
(a SquashFS overlay onto `/usr`) is the clean way to add a native binary. See the
README for the full rationale.

---

## 1. Install the sysext

On the ZimaOS host (`sudo` where shown — ZimaOS v1.7.0 disables root SSH login):

```bash
cd /tmp
git clone https://github.com/chicohaager/zimaos-tailscale-sysext
cd zimaos-tailscale-sysext
sudo ./install.sh
```

`install.sh` sanity‑checks the kernel, downloads the official Tailscale static
tarball (verifying its SHA‑256), builds a gzip‑squashfs `tailscale.raw`, installs
it to `/var/lib/extensions/`, and enables `tailscaled.service` **plus a boot‑order
watchdog** (ZimaOS merges sysexts *after* `multi-user.target`, so the in‑sysext
service needs the watchdog to start reliably at boot — details in the README).

After it finishes, `tailscaled` is running but **logged out**:

```
Status: "Needs login: "
```

---

## 2. Authenticate — read this before you type `tailscale up`

This is where most of the pain is. `tailscale up` is **blocking**: it prints a
login URL and then **keeps running** until you approve that URL in a browser. It
must stay alive to finish the handshake.

### ❌ The mistakes to avoid

- **Do not wrap it in `timeout`** and don't Ctrl‑C it after grabbing the URL. If
  the process dies before you authorize, the login never finalizes — the daemon
  stays `NeedsLogin` even though the admin console may briefly show the node as
  "online".
- **Do not run `tailscale up` again "to retry".** Each fresh `up` **regenerates
  the node key**, which de‑authorizes the previous one and creates a **duplicate
  machine entry** in your admin console. You end up with `myhost`, `myhost-1`,
  etc., and none of them logged in.

### ✅ The clean way

Run it in the foreground and leave it until you've clicked the link:

```bash
sudo tailscale up --accept-routes
# → visit the printed https://login.tailscale.com/a/******** URL, approve, done.
```

Prefer a non‑interactive/headless session? Launch it **detached** and read the URL
from the log — but still launch it **only once**:

```bash
sudo nohup tailscale up --accept-routes >/tmp/ts-up.log 2>&1 &
sleep 4 && grep -o 'https://login.tailscale.com/[a-zA-Z0-9/]*' /tmp/ts-up.log
```

Open that URL, approve the machine, and the still‑running process finalizes the
handshake.

### Verify it's really up (don't trust the console alone)

```bash
tailscale status          # your node should list an IP and no "offline" tag
tailscale ip -4           # prints the 100.x.y.z tailnet IP once Running
tailscale ip -6           # fd7a:…  — present on kernel 6.18.9, see the IPv6 row in section 5
```

From **another device on the same tailnet** you can prove the daemon is live with
a WireGuard‑level ping (a `pong` only comes back if the peer's `tailscaled` is
authenticated and connected):

```bash
tailscale ping <your-zimaos-node>
# pong from <node> (100.x.y.z) via ... in 1ms
```

### Housekeeping in the admin console

- **Delete any duplicate/stale machine entries** left over from earlier attempts.
- For an always‑on server, open the node → **Disable key expiry**, so you don't
  have to re‑authenticate in ~180 days.
- Note your node's **MagicDNS name** — `tailscale status` shows it. It's derived
  from the machine hostname (lowercased). You'll need the exact name for HTTPS.

---

## 3. Serve the ZimaOS WebUI over HTTPS

A MagicDNS name is **not automatically HTTPS**. The ZimaOS WebUI listens on plain
**HTTP :80**; nothing terminates TLS with a valid cert on :443. The native fix is
**`tailscale serve`**, which terminates TLS with an auto‑provisioned Let's Encrypt
certificate and proxies to your local service.

### 3.1 Enable HTTPS in your tailnet (one‑time, browser)

In the **admin console → DNS**:

- **MagicDNS**: enabled
- **HTTPS Certificates**: **Enable**

Without this, `tailscale serve` can't obtain a certificate.

### 3.2 Turn on the proxy (on the host)

```bash
sudo tailscale serve --bg 80
```

`--bg` runs it in the background (persisted in the daemon state). Check it:

```bash
tailscale serve status
# https://<node>.<tailnet>.ts.net (tailnet only)
# |-- / proxy http://127.0.0.1:80
```

Your WebUI is now at:

```
https://<node>.<tailnet>.ts.net/
```

### 3.3 Verify the certificate is genuinely valid

From any tailnet device (note: **no** `-k`):

```bash
curl -sS -o /dev/null -w "code=%{http_code} tls=%{ssl_verify_result}\n" \
  https://<node>.<tailnet>.ts.net/
# code=200 tls=0     ← tls=0 means the cert verified

echo | openssl s_client -connect <node>.<tailnet>.ts.net:443 \
  -servername <node>.<tailnet>.ts.net 2>/dev/null \
  | openssl x509 -noout -subject -issuer
# subject=CN = <node>.<tailnet>.ts.net
# issuer=C = US, O = Let's Encrypt, ...
```

To expose it to the public internet instead of tailnet‑only, use
`tailscale funnel` — but for a private NAS, keep it tailnet‑only.

**Turn it off:**

```bash
sudo tailscale serve --https=443 off
```

> ⚠️ **Common gotcha:** if `https://…` "doesn't work", check you're using the
> **live** node's MagicDNS name. Leftover duplicate machines from step 2 have
> their own names that resolve but serve nothing. `tailscale status` shows which
> node is actually yours.

---

## 4. Taildrop auto‑receiver (drop files onto the NAS)

Taildrop works out of the box between your own devices:

```bash
# from any device, send a file TO the ZimaOS box:
tailscale file cp ./photo.jpg <your-zimaos-node>:
```

But on a **headless Linux** host, incoming files sit in the daemon inbox until you
run `tailscale file get` — inconvenient for a NAS. The fix is a tiny systemd
service that runs `tailscale file get --loop` and writes everything into a folder
under `/DATA`.

### 4.1 Create the service

Save as `/etc/systemd/system/taildrop-receiver.service`:

```ini
[Unit]
Description=Taildrop auto-receiver (moves inbound Taildrop files to /DATA/taildrop-in)
Documentation=https://tailscale.com/kb/1106/taildrop
# tailscaled + the tailscale binary live inside the sysext, which merges AFTER
# multi-user.target on ZimaOS. We self-heal via Restart=always instead of a hard
# ordering dep: until the sysext is merged and tailscaled is up, `file get`
# errors and we simply retry.
After=tailscaled.service network-online.target
Wants=tailscaled.service
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStartPre=/bin/mkdir -p /DATA/taildrop-in
ExecStart=/usr/bin/tailscale file get --loop --conflict=rename --verbose /DATA/taildrop-in/
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Key choices:

- **`--loop`** — receives files continuously as they arrive (native flag, no polling script).
- **`--conflict=rename`** — same‑named files get a numeric suffix instead of being
  skipped or overwritten, so nothing is ever lost.
- **`Restart=always` + `StartLimitIntervalSec=0`** — self‑heals through the ZimaOS
  boot‑order quirk (the `tailscale` binary only exists after the sysext is merged).
- The unit lives on the **persistent root** (`/etc/systemd/system/`), not in the
  sysext, so it survives reboots and ZimaOS updates.

> **Tip for editing files over SSH+sudo on ZimaOS:** don't pipe into
> `sudo -S tee` — the password on stdin gets consumed by `tee` and truncates the
> file. Instead `scp` the file to `/tmp` first, then `sudo cp /tmp/... /etc/...`
> (`cp` reads no stdin).

### 4.2 Enable it

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now taildrop-receiver.service
systemctl is-active taildrop-receiver.service    # → active
```

### 4.3 Prove it works (auto, no manual `get`)

From another tailnet device:

```bash
echo "hello nas" > /tmp/proof.txt
tailscale file cp /tmp/proof.txt <your-zimaos-node>:
```

Within a couple of seconds, on the ZimaOS box:

```bash
ls -l /DATA/taildrop-in/
# -rw-r--r-- ... proof.txt
sudo journalctl -u taildrop-receiver.service -n 3
# ... wrote proof.txt as /DATA/taildrop-in/proof.txt (10 bytes)
# ... moved 1/1 files
```

No manual `tailscale file get` needed — the file lands by itself.

Sending **from** the ZimaOS box to another device works the same way:
`tailscale file cp <file> <other-device>:`.

---

## 5. ZimaOS‑specific things worth knowing

| Topic | Detail |
|---|---|
| **Read‑only root** | Only `/DATA` (and `/etc/systemd/system/`) are writable/persistent. Put state and units there. |
| **Boot order** | Sysexts merge *after* `multi-user.target`. Services from inside a sysext need a watchdog (or `Restart=always`) to start at boot — see README. |
| **`/DATA` is a late mount** | `/DATA` is a bind mount of `/var/lib/casaos_data` (`DATA.mount`), pulled in by `casaos-bind.target` — **not** by `local-fs.target`. Its `Before=multi-user.target` orders it before the *target*, not before that target's other `Wants=`, so any unit writing to `/DATA` must declare `RequiresMountsFor=/DATA/…` itself. Without it the unit races the mount, and because the root is read-only squashfs a `mkdir` fallback fails outright instead of silently landing in the wrong place. |
| **Start limits bite hard** | Default `RestartSec` is 100 ms and the default start limit is 5 starts / 10 s, so five instant failures latch a unit into `failed` in half a second (`Start request repeated too quickly`) and nothing retries it — a manual start much later then "works", which makes the bug look intermittent. For a boot-critical daemon use `RestartSec=5` + `StartLimitIntervalSec=0`, and `systemctl reset-failed` before any scripted `start`. |
| **IPv6** | **Works with kernel 6.18.9** (ZimaOS v1.6.2-beta2 and later, incl. stable v1.7.0): `CONFIG_IPV6_MULTIPLE_TABLES=y`, so Tailscale keeps tunneled IPv6 on and the node gets its `fd7a:115c:a1e0::…` address (verified with `curl -6` against tailnet peers). On **kernel 6.12.25 (v1.6.1)** the flag was absent and `tailscaled` logged `router: disabling tunneled IPv6 …` → IPv4‑only inside the tailnet; the fix there is a ZimaOS upgrade, not a module change. `tailscale netcheck` saying `IPv6: no, but OS has support` is about your ISP/LAN having no global IPv6 — unrelated to the kernel, and tailnet IPv6 works anyway. |
| **Auth state** | `/DATA/AppData/tailscale/` — survives reboots and ZimaOS upgrades. Re‑running `install.sh` reuses it. |
| **Node naming** | The node registers under the machine hostname (lowercased). After messy auth attempts you may see duplicates — clean them in the admin console and use `tailscale status` to identify the live one. |

---

## 6. Uninstall

`uninstall.sh` lives in the checkout from step 1 — and `/tmp` is a tmpfs, so after a reboot it is
gone. Clone it again (it is ~400 KB) and run it from there:

```bash
cd /tmp && git clone https://github.com/chicohaager/zimaos-tailscale-sysext
cd zimaos-tailscale-sysext

sudo ./uninstall.sh            # remove sysext, keep auth state
sudo ./uninstall.sh --purge    # also wipe /DATA/AppData/tailscale/
```

Remember to also remove the Taildrop receiver if you added it:

```bash
sudo systemctl disable --now taildrop-receiver.service
sudo rm -f /etc/systemd/system/taildrop-receiver.service
sudo systemctl daemon-reload
```

---

## TL;DR

```bash
# 1. install
cd /tmp && git clone https://github.com/chicohaager/zimaos-tailscale-sysext
cd zimaos-tailscale-sysext && sudo ./install.sh

# 2. authenticate — ONCE, leave it running until you approve the URL
sudo tailscale up --accept-routes

# 3. HTTPS WebUI  (enable MagicDNS + HTTPS Certificates in the admin console first)
sudo tailscale serve --bg 80
#    → https://<node>.<tailnet>.ts.net/

# 4. Taildrop auto-receive → /DATA/taildrop-in/
sudo systemctl enable --now taildrop-receiver.service
```

*Module: [chicohaager/zimaos-tailscale-sysext](https://github.com/chicohaager/zimaos-tailscale-sysext) · MIT.*
