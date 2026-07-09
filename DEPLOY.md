# Taking Good News Bears live (GitHub Pages)

This publishes your site to a real URL and rebuilds it **daily in the cloud** — your
Mac does not need to be on. Total cost: just the domain.

Everything here you do once. I've already prepared the files (`generate.pl`,
`index.html`, and `.github/workflows/refresh.yml`).

---

## 1. Create a GitHub account (free)
Go to https://github.com and sign up (skip if you have one).

## 2. Create a repository
- Click **New repository**.
- Name it e.g. `good-news-bears`.
- Set it to **Public** (GitHub Pages is free on public repos).
- Do **not** add a README/license (we already have files).
- Click **Create repository**.

## 3. Push this project to it
In Terminal, from this folder (`/Users/KATHY/GOOD NEWS`):

```bash
git init
git add -A
git commit -m "Good News Bears"
git branch -M main
git remote add origin https://github.com/<YOUR-USERNAME>/good-news-bears.git
git push -u origin main
```

Replace `<YOUR-USERNAME>`. GitHub will ask you to sign in the first time.

## 4. Turn on Pages
- In the repo: **Settings → Pages**.
- Under **Build and deployment → Source**, choose **GitHub Actions**.

That's it — the workflow runs on push. Watch it under the **Actions** tab. When it
finishes (~1 min), your site is live at:

```
https://<YOUR-USERNAME>.github.io/good-news-bears/
```

Because this is a real host (not the preview sandbox), the **news photos load** here —
this is the full version, not the text-only share build.

## 5. Confirm the daily refresh
The site rebuilds automatically every day (see the `cron` line in
`.github/workflows/refresh.yml`). You can also trigger it any time:
**Actions → Refresh Good News Bears → Run workflow**.

To change the time, edit the `cron` value. It's in **UTC**: `0 11 * * *` is 11:00 UTC.
- 7 AM US Eastern ≈ `0 11 * * *` (summer) / `0 12 * * *` (winter)
- 7 AM US Pacific ≈ `0 14 * * *` (summer) / `0 15 * * *` (winter)

---

## 6. Connect your custom domain

### Buy it
I can't purchase it for you (it needs your account + payment). Buy **goodnewsbears.news**
at a registrar — good options:
- **Porkbun** — https://porkbun.com  (usually the best `.ai` price)
- **Namecheap** — https://www.namecheap.com
- **Cloudflare** — https://www.cloudflare.com (at-cost pricing)

Note: `.ai` has a **2-year minimum**, roughly **$60–110** total.

### Point it at GitHub Pages
Once you own it, at your registrar's DNS settings add:

**Apex domain (`goodnewsbears.news`)** — four `A` records:
```
A   @   185.199.108.153
A   @   185.199.109.153
A   @   185.199.110.153
A   @   185.199.111.153
```
(If the registrar supports `ALIAS`/`ANAME` at the apex, you may point it to
`<YOUR-USERNAME>.github.io` instead.)

**www subdomain** — one `CNAME`:
```
CNAME   www   <YOUR-USERNAME>.github.io
```

### Tell GitHub about it
- **Settings → Pages → Custom domain** → enter `goodnewsbears.news` → **Save**.
- Also uncomment the `CNAME` line in `.github/workflows/refresh.yml` and set it to your
  domain, so each daily rebuild keeps the domain attached.
- Check **Enforce HTTPS** once the certificate is issued (can take a few minutes to an hour).

DNS changes can take from a few minutes up to ~24 hours to propagate.

---

## Troubleshooting
- **Actions run failed?** Open the run under the **Actions** tab and read the log. The
  most common cause is a feed temporarily blocking the runner — it usually self-heals
  on the next run.
- **Site 404s right after setup?** Give it a minute after the first successful deploy,
  then hard-refresh.
- **Private repo?** GitHub Pages needs a paid plan for private repos — keep it public
  (all the content is public news links anyway).
