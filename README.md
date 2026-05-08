# zimaos-tailscale-sysext

**Tailscale als natives systemd-sysext-Modul für ZimaOS.** Kein Docker-Container — der Tailscale-Daemon läuft direkt auf dem Host mit echtem TUN, vollwertigem Subnet-Router/Exit-Node-Support und Boot-Persistenz.

> 🇬🇧 English version: [README.en.md](README.en.md)

---

## Was das hier ist (und warum)

ZimaOS basiert auf Buildroot und hat einen **read-only Root-Filesystem**. Es gibt keinen Paketmanager (kein `apt`, kein `yum`), und der ZimaOS-Sourcecode ist nicht öffentlich — ein klassisches Buildroot-Paket einzureichen ist also kein gangbarer Weg.

Der saubere Mechanismus für native Erweiterungen auf ZimaOS heißt **`systemd-sysext`**: ein SquashFS-Overlay nach `/usr` zur Laufzeit, ohne den read-only Root anzufassen. ZimaOS nutzt das selbst (z. B. `cron.raw`, `casadrop.raw`, `xpkg.raw`), und Drittanbieter-Module sind erlaubt.

Dieses Repo packt Tailscale als ebensolches Modul. Das Install-Layout entspricht **1:1 dem offiziellen Buildroot-Rezept** [`package/tailscale/tailscale.mk`](https://github.com/buildroot/buildroot/blob/master/package/tailscale/tailscale.mk):

| | Buildroot `tailscale.mk` | dieser Sysext |
|---|---|---|
| `/usr/bin/tailscaled` | Binary | Binary (aus offiziellem Static-Tarball) |
| `/usr/sbin/tailscaled` | Symlink → `../bin/tailscaled` | identisch |
| `/usr/bin/tailscale` | CLI | CLI |
| `/usr/lib/systemd/system/tailscaled.service` | Unit | Unit (angepasst, s. u.) |
| State | `/var/lib/tailscale` (StateDirectory) | `/DATA/AppData/tailscale/` (ZimaOS-Anpassung) |
| Kompilation | Cross-Compile mit Buildroot-Go | Upstream-Static-Binary |

Verifiziert auf **ZimaOS v1.6.1, Kernel 6.12.25, ZimaCube** (2026-05-08).

---

## Voraussetzungen

- ZimaOS x86_64 (für ARM-Boards: `ARCH=arm64` setzen)
- Kernel hat `TUN`, `NF_TABLES`, `NF_NAT`, `NF_CONNTRACK`, `NETFILTER` (auf ZimaOS v1.6.1 alle vorhanden)
- Schreibzugriff auf `/var/lib/extensions/` (sudo)
- Internetzugriff zum Laden des Tailscale-Tarballs

> ### ⚠ Bekannte IPv6-Limitierung (ZimaOS-Kernel-Sache, nicht dieses Modul)
>
> ZimaOS' Kernel-Image hat einige für vollständige IPv6-Tailscale-Funktion nötige `CONFIG_*`-Flags **nicht** aktiviert. **Sysext kann das nicht fixen** — die Flags müssen im Kernel-Image gesetzt sein, bevor der Kernel kompiliert wurde.
>
> **Konkrete Auswirkung:** Tailscale deaktiviert IPv6-Tunneling automatisch und loggt:
>
> ```
> router: disabling tunneled IPv6 due to system IPv6 config:
>   kernel doesn't support IPv6 policy routing
> ```
>
> Mesh-VPN über IPv4, IPv4-Subnet-Router und IPv4-Exit-Node funktionieren **uneingeschränkt**. Nur IPv6-Verbindungen über das Tailnet sind aus.
>
> **Audit auf ZimaOS v1.6.1 / Kernel 6.12.25:**
>
> | Config | Status | Wirkung |
> |---|---|---|
> | `CONFIG_IPV6_MULTIPLE_TABLES` | ❌ not set | 🔴 IPv6-Tunneling komplett deaktiviert |
> | `CONFIG_IPV6_SUBTREES` | ❌ not present | 🟡 keine source-prefix-Routes |
> | `CONFIG_NETFILTER_XT_TARGET_MARK` | ❌ not set | 🟡 kein iptables `-j MARK` |
> | `CONFIG_IP6_NF_TARGET_MASQUERADE` | ❌ not set | 🟡 kein IPv6-Subnet-Router-Masquerading |
> | `CONFIG_IP_MULTIPLE_TABLES`, `CONFIG_NETFILTER_XT_MARK`, `CONFIG_NETFILTER_XT_MATCH_MARK`, `CONFIG_IP6_NF_IPTABLES/FILTER/MANGLE` | ✅ aktiv | – |
>
> **Was du tun kannst:** Den Kernel-Config-Request bei IceWhale einreichen — Vorlage in [`mod-store/ICEWHALE_KERNEL_REQUEST.md`](mod-store/ICEWHALE_KERNEL_REQUEST.md). Je mehr 👍 das Issue bekommt, desto höher die Chance.

---

## Schnell-Installation

```bash
# Auf dem ZimaOS-Host als root (oder via sudo):
sudo ./install.sh
```

Der Installer

1. prüft den Host (Kernel-Module, Squashfs-Compression, vorhandene Tailscale-Container),
2. lädt den offiziellen Tailscale-Static-Tarball von `pkgs.tailscale.com`,
3. baut `tailscale.raw` (gzip-SquashFS, ca. 35 MB),
4. installiert nach `/var/lib/extensions/`,
5. aktiviert `tailscaled.service` automatisch.

Anschließend:

```bash
sudo tailscale up
```

und die ausgegebene Login-URL im Browser öffnen.

### Direkt via curl (sobald das Repo öffentlich ist)

```bash
curl -fsSL https://raw.githubusercontent.com/chicohaager/zimaos-tailscale-sysext/main/install.sh \
  | sudo REPO_RAW=https://raw.githubusercontent.com/chicohaager/zimaos-tailscale-sysext/main bash
```

---

## Manuelle Installation

```bash
# 1. Bauen (auf einem beliebigen Linux mit mksquashfs, oder direkt auf dem ZimaOS-Host)
./build.sh                              # neueste stabile Version
TAILSCALE_VERSION=1.96.4 ./build.sh     # gepinnt

# 2. Hochladen auf den ZimaOS-Host (falls woanders gebaut)
scp tailscale.raw Holgi@zimaos:/tmp/

# 3. Auf dem ZimaOS-Host als root:
sudo cp /tmp/tailscale.raw /var/lib/extensions/
sudo systemd-sysext refresh
sudo systemctl daemon-reload
sudo systemctl enable --now tailscaled
sudo tailscale up
```

---

## Konfiguration

### Subnet-Router

Damit andere Geräte im Tailnet dein lokales LAN (z. B. `192.168.1.0/24`) erreichen können:

```bash
sudo tailscale up --advertise-routes=192.168.1.0/24 --accept-routes
```

Anschließend in der Tailscale-Admin-Konsole die Routes „approven".

### Exit-Node

Den ZimaOS-Host als VPN-Exit-Node anbieten:

```bash
sudo tailscale up --advertise-exit-node
```

In der Admin-Konsole approven, dann auf einem Client mit `tailscale up --exit-node=<host>` nutzen.

### Service-Flags überschreiben

Die Unit liest optional `/etc/default/tailscaled`:

```bash
# /etc/default/tailscaled
PORT="41641"
FLAGS="--advertise-routes=192.168.1.0/24 --accept-routes"
```

Nach Änderung:

```bash
sudo systemctl restart tailscaled
```

### IP-Forwarding (für Subnet-Router/Exit-Node)

Permanent aktivieren:

```bash
echo 'net.ipv4.ip_forward = 1'   | sudo tee -a /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo sysctl --system
```

---

## Persistenz & Update-Verhalten

- **Sysext-Datei** liegt unter `/var/lib/extensions/tailscale.raw`. Dieser Pfad ist trotz `/var`-Präfix **persistent** — er ist ein Bind-Mount von `/var/lib/casaos_data/.extensions/` auf der ext4-Partition.
- **Auth-State** liegt unter `/DATA/AppData/tailscale/` (ext4, persistent).
- **ZimaOS-Update:** Nach einem ZimaOS-Upgrade einfach `install.sh` erneut ausführen (oder die `.raw` neu bauen und kopieren). Der Auth-State bleibt erhalten.
- **Reboot:** `systemd-sysext.service` lädt die Extension automatisch, `tailscaled.service` startet automatisch.

---

## Deinstallation

```bash
sudo ./uninstall.sh           # Sysext entfernen, State (/DATA/AppData/tailscale/) erhalten
sudo ./uninstall.sh --purge   # Alles weg inkl. Auth-State
```

---

## Troubleshooting

| Symptom | Ursache | Fix |
|---|---|---|
| `systemd-sysext refresh` → `Invalid argument` | `.raw` mit zstd komprimiert (ZimaOS-Kernel hat kein SQUASHFS_ZSTD) | `mksquashfs ... -comp gzip` (build.sh macht das automatisch) |
| `tailscaled.service inactive`, aber Tailscale läuft offenbar | Parallel laufender Docker-Container `tailscale/tailscale` | `docker stop tailscale && docker update --restart=no tailscale` |
| Service startet, aber `BackendState=NeedsLogin` | normal nach Erst-Install | `sudo tailscale up` |
| Subnet-Router-Routes funktionieren nicht | IP-Forwarding nicht aktiv | siehe „IP-Forwarding" oben |
| Log: `disabling tunneled IPv6 due to system IPv6 config` | Kernel hat `CONFIG_IPV6_MULTIPLE_TABLES` nicht gesetzt | Kernel-seitig — ZimaOS-Image-Update von IceWhale nötig. Bug-Report: [`mod-store/ICEWHALE_KERNEL_REQUEST.md`](mod-store/ICEWHALE_KERNEL_REQUEST.md) |
| `tailscale netcheck` zeigt `IPv6: no, but OS has support` | gleiche Ursache wie oben | dito |

Logs:

```bash
sudo journalctl -u tailscaled -f
sudo tailscale netcheck
```

---

## Lizenz

MIT (siehe [LICENSE](LICENSE)). Tailscale-Binaries sind BSD-3-Clause (Tailscale Inc.); siehe [NOTICE](NOTICE).

---

## Inspiration / Verwandtes

- Buildroot-Rezept: [package/tailscale/tailscale.mk](https://github.com/buildroot/buildroot/blob/master/package/tailscale/tailscale.mk)
- Existierende ZimaOS-Drittanbieter-sysexts: [chicohaager/cron](https://github.com/chicohaager/cron) (Vorbild für Mod-Store-Submission)
- ZimaOS Mod-Store: [IceWhaleTech/Mod-Store](https://github.com/IceWhaleTech/Mod-Store)
