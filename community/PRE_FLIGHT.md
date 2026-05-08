# Pre-flight checklist before publishing

Run through this once before `gh repo create --public` (or before flipping a private repo to public).

---

## 1. Replace placeholders globally

Search for `<DEIN-USER>` and `CHANGE-ME` in the working tree and substitute your actual GitHub handle / org:

```bash
# Dry-run grep first
grep -rn --exclude-dir=.git -e '<DEIN-USER>' -e 'CHANGE-ME' .

# When you've decided on the username:
GH_USER=your-github-handle
sed -i "s|<DEIN-USER>|${GH_USER}|g; s|CHANGE-ME|${GH_USER}|g" \
  README.md README.en.md install.sh \
  mod-store/entry.json mod-store/PR_TEMPLATE.md mod-store/ICEWHALE_KERNEL_REQUEST.md \
  community/LAUNCH_PLAN.md community/posts/*.md
git diff   # review
git commit -am "Resolve placeholder GitHub handles to ${GH_USER}"
```

---

## 2. Identity check

```bash
git config user.name
git config user.email
```

Make sure the email matches the one you've registered on GitHub (or set `git config user.email` to one of your noreply-IDs if you prefer to keep your private email out of public commit metadata).

GitHub's noreply pattern: `<userid>+<username>@users.noreply.github.com` — see <https://github.com/settings/emails>.

---

## 3. Final scan for accidental leakage

Run from the repo root:

```bash
# Secrets, real IPs, real emails
grep -rIEn --exclude-dir=.git \
  '(password|secret|token|api[_-]?key|bearer|private[_-]?key|BEGIN [A-Z ]*PRIVATE KEY)' .

# Your private tailnet IP, hostnames, mail addresses
grep -rIEn --exclude-dir=.git \
  '100\.110\.|holgi1811@|holger\.kuehn@|192\.168\.1\.(82|143|147|181)' .
```

Both should return zero hits (or only documented placeholders).

---

## 4. Build artifacts must not be in the index

```bash
git ls-files | grep -E '\.(raw|tgz|cast)$'
```

Should be empty. If anything shows up, remove it with `git rm --cached <file>` and re-commit.

---

## 5. Create the public repo + first release

```bash
gh repo create zimaos-tailscale-sysext --public --source=. --remote=origin --push

# Build a fresh .raw for the release asset (don't reuse the one in your working dir
# if you've changed source files — rebuild for a deterministic match):
TAILSCALE_VERSION=1.96.4 ./build.sh

gh release create v1.0.0 tailscale.raw \
  --title "v1.0.0 — Tailscale 1.96.4 sysext for ZimaOS" \
  --notes-file community/posts/00-github-release-notes.md
```

---

## 6. Smoke-test the public install path

In a fresh shell, on the ZimaOS host (or a VM):

```bash
git clone https://github.com/<your-handle>/zimaos-tailscale-sysext
cd zimaos-tailscale-sysext
sudo ./install.sh
```

This validates that the public repo + the README install steps actually work end-to-end — important before announcing.

---

## 7. Announce in the recommended order

See [`LAUNCH_PLAN.md`](LAUNCH_PLAN.md). TL;DR:

1. Mod-Store PR (the money shot)
2. ZimaOS forum post
3. ZimaOS Discord announce

Then 24–48 h later, optionally Reddit / Tailscale forum / Bluesky / HN.

---

## 8. Aftercare

- Subscribe to your own GitHub issues + watch the Mod-Store PR for review feedback.
- Re-run `./build.sh` whenever Tailscale ships a new stable release; cut a new tag (`v1.x.y`), re-attach the rebuilt `.raw`. The `mod-v2.json` entry will pick up the new release automatically if you used the `repo:` form.
- If IceWhale acts on the kernel-config request (`mod-store/ICEWHALE_KERNEL_REQUEST.md`), file the actual issue on `IceWhaleTech/ZimaOS` once it's been lightly discussed in the forum thread — gives the issue a stronger context anchor.
