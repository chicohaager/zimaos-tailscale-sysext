# Launch-Plan — empfohlene Reihenfolge

Alles unter `posts/` ist drop-in-fertig. **Fülle nur `<DEIN-USER>` und Release-Tag aus, dann Copy & Paste.**

---

## Schritt 0 — GitHub-Repo public + Release (Voraussetzung)

```bash
cd ~/dev/zimaos-tailscale-sysext
git init -b main
git add .
git commit -m "v1.0.0 — initial release"
gh repo create zimaos-tailscale-sysext --public --source=. --remote=origin --push
gh release create v1.0.0 tailscale.raw \
  --title "v1.0.0 — Tailscale 1.96.4 sysext for ZimaOS" \
  --notes-file community/posts/00-github-release-notes.md
```

Danach in `README.md`/`README.en.md`/`install.sh` alle `<DEIN-USER>` / `CHANGE-ME` Platzhalter auf den echten User-/Org-Namen ersetzen und committen.

⏱ Zeit: ~5 min.

---

## Schritt 1 — Mod-Store PR (das ist der Money-Shot)

```bash
# Fork klonen, Eintrag hinzufügen, PR
gh repo fork IceWhaleTech/Mod-Store --clone --remote
cd Mod-Store
# In mod-v2.json den Tailscale-Eintrag als JSON-Objekt anhängen
# (siehe community/posts/01-mod-store-pr-body.md für genauen JSON-Snippet)
git checkout -b add-tailscale
git commit -am "Add tailscale community sysext"
gh pr create --title "Add tailscale community sysext module" \
  --body-file ../zimaos-tailscale-sysext/community/posts/01-mod-store-pr-body.md
```

**Wenn das gemergt wird, ist Tailscale für jeden ZimaOS-User 1-Klick-installierbar im UI.** Das ist die wichtigste Aktion.

⏱ Zeit: ~10 min.

---

## Schritt 2 — ZimaOS Community Forum

→ <https://community.zimaspace.com/>
1. Account erstellen / einloggen
2. Neuer Topic in „Apps & Modules" oder ähnlicher Sektion
3. Inhalt aus `posts/02-zimaspace-forum-de.md` (oder `-en.md`) kopieren

⏱ Zeit: ~15 min.

---

## Schritt 3 — ZimaOS Discord

→ <https://discord.gg/f9nzbmpMtU>
- Channel `#community-projects` (oder `#general`, je nach Server-Layout)
- Inhalt aus `posts/03-discord-announce.md` kopieren

⏱ Zeit: ~5 min.

---

## Optional Phase B (24–48 h später, wenn #1–#3 Resonanz haben)

| Schritt | Datei | Kanal |
|---------|-------|-------|
| 4 | `posts/04-reddit-selfhosted.md` | r/selfhosted (Wochenende = bessere Sichtbarkeit) |
| 5 | dito, cross-post | r/homelab |
| 6 | `posts/05-tailscale-forum.md` | <https://forum.tailscale.com/> (Community Showcase) |
| 7 | `posts/06-bluesky-mastodon-x.md` | drei kurze 280-Zeichen-Posts |
| 8 | `posts/07-hackernews-show-hn.md` | nur bei wirklicher Traktion |

Optional: Asciinema-Demo (Skript in `posts/08-asciinema-script.md`) — verlinkt aus Reddit/Tweets, multipliziert Reichweite.

---

## Was du **nicht** tun solltest

- ❌ Alle Kanäle gleichzeitig fluten — wirkt spammig, und du kannst auf Diskussionen nicht parallel reagieren.
- ❌ Reddit ohne Demo — Selfhosted-Subreddit ist visuell-verwöhnt; ein Asciinema-Cast oder Screenshot drosselt die „looks fishy"-Reaktion.
- ❌ HN posten bevor #1–#3 Anlauf-Diskussion haben — HN-Comments können brutal sein, du willst belastbare Antworten parat.
- ❌ Den Bug-Report (`mod-store/ICEWHALE_KERNEL_REQUEST.md`) als separates Issue VOR dem Mod-Store-PR einreichen — IceWhale sieht dann zwei unverbundene Tickets statt eines kohärenten Beitrags.
