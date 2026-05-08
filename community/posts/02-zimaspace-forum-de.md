# [Module] Tailscale nativ auf ZimaOS — als systemd-sysext

Hi zusammen,

ich habe Tailscale als natives `systemd-sysext`-Modul für ZimaOS gepackt. Falls jemand Tailscale bisher per Docker-Container betreibt und sich an den Limitierungen (`--tun=userspace-networking`, kein vollwertiger Subnet-Router, kein sauberer Exit-Node) gestört hat — das hier läuft direkt auf dem Host als regulärer Systemd-Service, mit echtem TUN.

**Repo:** <https://github.com/<DEIN-USER>/zimaos-tailscale-sysext>

## Was ist drin

- `build.sh` — baut deterministisch eine `tailscale.raw` aus dem offiziellen Tailscale-Static-Tarball
- `install.sh` — One-Shot-Installer auf dem ZimaOS-Host (Sanity-Checks → Build → Deploy → Service-Enable)
- `uninstall.sh` — sauberer Rückbau, Auth-State unter `/DATA/AppData/tailscale/` bleibt optional erhalten
- README in DE+EN, MIT-Lizenz, Mod-Store-Submission-Vorlage

Layout entspricht 1:1 dem upstream Buildroot-Rezept `package/tailscale/tailscale.mk` — d.h. `tailscaled` unter `/usr/bin/`, Symlink in `/usr/sbin/`, Unit unter `/usr/lib/systemd/system/`. Die einzige ZimaOS-Anpassung: State landet unter `/DATA/AppData/tailscale/` statt `/var/lib/tailscale/`, weil `/var/` auf ZimaOS tmpfs ist.

## Schnell-Install

```bash
git clone https://github.com/<DEIN-USER>/zimaos-tailscale-sysext
cd zimaos-tailscale-sysext
sudo ./install.sh
sudo tailscale up
```

Anschließend Login-URL im Browser öffnen — fertig. Reboot überlebt das Modul automatisch (`/var/lib/extensions/` ist auf ZimaOS ein Bind-Mount auf der ext4-Partition, kein tmpfs — `systemd-sysext.service` lädt's beim Boot wieder).

## Verifiziert

ZimaOS v1.6.1 / Kernel 6.12.25 / ZimaCube, Tailscale 1.96.4.

## Bekannte Einschränkung: IPv6

Der ZimaOS-Kernel hat aktuell `CONFIG_IPV6_MULTIPLE_TABLES` (und ein paar verwandte Flags) **nicht** aktiviert. Tailscale loggt dadurch beim Start `disabling tunneled IPv6 due to system IPv6 config` und schaltet IPv6-Tunneling ab. **IPv4-Mesh, Subnet-Router und Exit-Node funktionieren uneingeschränkt.** Ein fertiger Bug-Report-Text für IceWhale liegt im Repo unter `mod-store/ICEWHALE_KERNEL_REQUEST.md` — wenn ihr das Issue mit 👍 unterstützt, steigen die Chancen auf einen Kernel-Fix in einem späteren ZimaOS-Update.

## Mod-Store-PR

Parallel habe ich einen PR an `IceWhaleTech/Mod-Store` offen, damit das Modul später als 1-Klick-Installation im ZimaOS-UI auftaucht. Sobald gemergt, ist hier kein git/build mehr nötig.

Feedback und Bug-Reports gerne als GitHub-Issue oder hier im Thread.

— Holger
