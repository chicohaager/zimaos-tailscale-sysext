# Launch plan — recommended order

Everything under `posts/` is drop-in ready. The GitHub handle is already set to `chicohaager` — only the release tag needs to be filled in, then copy & paste.

> Note: GitHub repo + release `v1.0.0` are already published — Step 0 is just the recap.

---

## Step 0 — GitHub repo public + release (prerequisite — done)

```bash
cd ~/dev/zimaos-tailscale-sysext
gh repo create zimaos-tailscale-sysext --public --source=. --remote=origin --push
TAILSCALE_VERSION=1.96.4 ./build.sh    # produces a fresh tailscale.raw
gh release create v1.0.0 tailscale.raw \
  --title "v1.0.0 — Tailscale 1.96.4 sysext for ZimaOS" \
  --notes-file community/posts/00-github-release-notes.md
```

⏱ Time: ~5 min.

---

## Step 1 — Mod-Store PR (this is the money shot)

```bash
# Fork the repo, add the entry, open the PR
gh repo fork IceWhaleTech/Mod-Store --clone --remote
cd Mod-Store
# Append the tailscale entry to mod-v2.json
# (see community/posts/01-mod-store-pr-body.md for the JSON snippet)
git checkout -b add-tailscale
git commit -am "Add tailscale community sysext"
gh pr create --title "Add tailscale community sysext module" \
  --body-file ../zimaos-tailscale-sysext/community/posts/01-mod-store-pr-body.md
```

**If this gets merged, Tailscale becomes a 1-click install in the ZimaOS UI for every ZimaOS user.** This is the single most impactful step.

⏱ Time: ~10 min.

---

## Step 2 — ZimaOS Community Forum

→ <https://community.zimaspace.com/>
1. Create an account / sign in
2. New topic under "Apps & Modules" (or the closest equivalent section)
3. Paste content from `posts/02-zimaspace-forum-en.md` (or `-de.md` if you prefer to address the German subset of the community)

⏱ Time: ~15 min.

---

## Step 3 — ZimaOS Discord

→ <https://discord.gg/f9nzbmpMtU>
- Channel `#community-projects` (or `#general`, depending on the server layout)
- Paste content from `posts/03-discord-announce.md`

⏱ Time: ~5 min.

---

## Optional — Phase B (24–48 h later, once Steps 1–3 have traction)

| Step | File | Channel |
|------|------|---------|
| 4 | `posts/04-reddit-selfhosted.md` | r/selfhosted (weekend = better visibility) |
| 5 | same content, cross-post | r/homelab |
| 6 | `posts/05-tailscale-forum.md` | <https://forum.tailscale.com/> (Community Showcase) |
| 7 | `posts/06-bluesky-mastodon-x.md` | three short ≤280-char posts |
| 8 | `posts/07-hackernews-show-hn.md` | only once you have real engagement |

Optional: an asciinema demo (script in `posts/08-asciinema-script.md`) — embeddable in Reddit/Bluesky posts, multiplies reach.

---

## What you should **not** do

- ❌ Flood every channel at once — looks spammy and you can't keep up with parallel discussions.
- ❌ Post to Reddit without a demo — the selfhosted subreddit is visually demanding; an asciinema cast or screenshot kills the "looks fishy" reaction.
- ❌ Post to HN before Steps 1–3 have any momentum — HN comments are brutal on Show-HNs with no engagement signals.
- ❌ File the kernel-config request (`mod-store/ICEWHALE_KERNEL_REQUEST.md`) as a separate issue **before** the Mod-Store PR — IceWhale would see two disconnected tickets instead of one coherent contribution. File it after the PR is at least under discussion.
