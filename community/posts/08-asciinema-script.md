# Asciinema demo script (~ 60 seconds)

A 60-second cast multiplies reach on Reddit/Bluesky/X dramatically. asciinema is preferred over video because it's text-searchable and embeds directly into READMEs.

## Recording

```bash
# On any ZimaOS host (or in a clean VM with a fake /proc/config.gz)
asciinema rec -t "Tailscale on ZimaOS via sysext" tailscale-sysext-demo.cast
```

Then run the steps below, line by line, with ~1 sec breathing space between commands. Save and upload via `asciinema upload tailscale-sysext-demo.cast` — get the public URL.

## Script (target: 60 seconds, ~10 lines visible)

```bash
# 1. State of the host (5 s)
$ uname -r && cat /etc/os-release | grep PRETTY
6.12.25
PRETTY_NAME="ZimaOS v1.6.1"

# 2. Show the existing sysext modules — context for the audience (5 s)
$ ls /var/lib/extensions/
casadrop.raw  cron.raw  web-ftp-client.raw  xpkg.raw  zimaos_ai.raw

# 3. The repo + one-shot installer (5 s)
$ git clone https://github.com/<DEIN-USER>/zimaos-tailscale-sysext && cd zimaos-tailscale-sysext

# 4. Install (~ 30 s — most of the cast)
$ sudo ./install.sh
═══ ZimaOS Tailscale-Sysext Installer ═══
▶ Host:    ZimaOS (x86_64, kernel 6.12.25)
▶ OS:      ZimaOS v1.6.1
⚠ IPv6 limitation detected: ...
▶ Tailscale version: 1.96.4 (amd64)
▶ Downloading https://pkgs.tailscale.com/stable/tailscale_1.96.4_amd64.tgz
▶ Packing /tmp/.../tailscale.raw
✓ Built: tailscale.raw  (Size: 35M)
▶ Installing → /var/lib/extensions/tailscale.raw
▶ Refreshing sysext overlay
▶ Enabling tailscaled.service
✓ Tailscale is installed but not yet authenticated. Next step: sudo tailscale up

# 5. Authenticate (5 s)
$ sudo tailscale up
To authenticate, visit: https://login.tailscale.com/a/abc123
...
Success.

# 6. The proof — Tailscale is alive on the host as a real systemd service (10 s)
$ tailscale status
100.x.y.z       zimacube         <user>@   linux    -

$ systemctl status tailscaled --no-pager | head -3
● tailscaled.service - Tailscale node agent
  Active: active (running)
```

> Replace `100.x.y.z` and `<user>` with whatever your demo host actually shows — but **don't include your real tailnet IP or login** in a public asciinema cast. They identify your device on the tailnet.

## Embed in README

Add to top of README.md after the title:

```markdown
[![asciicast](https://asciinema.org/a/<ID>.svg)](https://asciinema.org/a/<ID>)
```

## Why asciinema beats video here

- 200 KB cast vs. 20 MB video
- text-selectable inside the player
- README rendering via SVG fallback
- no YouTube algorithm, no expiring links
