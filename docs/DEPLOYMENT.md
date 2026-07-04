# Deployment (free tier, mobile-browser ready)

This guide puts Memory Circle fully online at no cost so family members can
test it from any phone browser, while you keep developing locally and ship
changes with a plain `git push`.

## Architecture

```text
GitHub repo (source of truth, push to deploy both halves)
 ├─ GitHub Actions → GitHub Pages     Flutter web app (HTTPS, mobile browsers)
 └─ Render free web service           FastAPI backend (auto-deploys on push)
      └─ Neon free Postgres           accounts, circles, memories, albums,
                                      AND photo bytes (ASSET_STORAGE=db)
```

Photos are stored inside Postgres (`ASSET_STORAGE=db`) because free hosts
wipe their local disk on every restart/deploy. Locally you keep the default
(`ASSET_STORAGE=disk`) with SQLite — nothing about your dev loop changes.

## One-time setup

### 1. Push the repo to GitHub

The repo must be **public** for free GitHub Pages.

```bash
cd /Volumes/HD-PGF-A/MemoryCircle
git remote add origin https://github.com/<YOUR_USERNAME>/MemoryCircle.git
git push -u origin main
```

### 2. Create the free database (Neon)

1. Sign up at https://neon.tech (free, no card).
2. Create a project (e.g. `memory-circle`).
3. Copy the connection string (looks like
   `postgresql://user:pass@ep-xxx.neon.tech/neondb?sslmode=require`).

### 3. Deploy the backend (Render)

1. Sign up at https://render.com (free, no card) and connect GitHub.
2. Choose **New → Blueprint** and select this repository — Render reads
   `render.yaml` and creates the `memory-circle-api` free service.
3. When prompted, paste the Neon connection string as `DATABASE_URL`.
4. After the first deploy, note your API URL, e.g.
   `https://memory-circle-api.onrender.com`, and open
   `https://.../health` to confirm `{"status": "ok"}`.

Every future `git push` to `main` redeploys the backend automatically.

### 4. Deploy the web app (GitHub Pages)

1. In the GitHub repo: **Settings → Pages → Source: GitHub Actions**.
2. **Settings → Secrets and variables → Actions → Variables** → add
   repository variable `API_BASE` = your Render URL
   (e.g. `https://memory-circle-api.onrender.com`, no trailing slash).
3. Push to `main` (or run the "Deploy web app to GitHub Pages" workflow
   manually). The app appears at
   `https://<YOUR_USERNAME>.github.io/MemoryCircle/`.

Share that URL with family — it works in any phone browser over HTTPS.

### 5. (Optional) Seed demo data into the online database

Run the seed locally but pointed at Neon:

```bash
cd backend/api
source .venv/bin/activate
pip install "psycopg[binary]"
DATABASE_URL="<neon connection string>" ASSET_STORAGE=db python3 -c \
  "from app.seed import run_seed; print(run_seed(reset=False))"
```

## Day-to-day workflow

```bash
# develop locally exactly as before
cd backend/api && source .venv/bin/activate && python3 -m uvicorn app.main:app --reload
cd apps/mobile_desktop_flutter && flutter run -d chrome --dart-define=API_BASE=http://127.0.0.1:8000

# ship to everyone
git add -A && git commit -m "describe the change" && git push
```

The push triggers both the Pages build (web app) and the Render deploy
(API). No other steps.

## Free-tier behavior to expect

- **Render free** sleeps after ~15 minutes idle; the first request then
  takes up to a minute. Tell testers the first open can be slow, or add a
  free uptime ping (e.g. https://uptimerobot.com or https://cron-job.org
  hitting `/health` every 10 minutes).
- **Neon free** gives ~0.5 GB storage. Display photos are ~200–400 KB each,
  so that is roughly a thousand photos — plenty for testing. Check usage in
  the Neon dashboard.
- **GitHub Pages** requires the repo to be public on a free account.

## Alternatives (also free)

- **Hugging Face Spaces** (Docker) can host the API; pair with Neon the
  same way. Spaces sleep after ~48 h idle.
- **Cloudflare Pages** can host the web build from a *private* repo if you
  do not want the code public.
- **Oracle Cloud Always Free VM** gives a permanent server (SQLite + disk
  storage work unchanged) at the cost of more setup and self-managed HTTPS.

## Environment variables reference (backend)

| Variable        | Default                          | Notes                                  |
|-----------------|----------------------------------|----------------------------------------|
| `DATABASE_URL`  | `sqlite:///./memory_circle.db`   | Any SQLAlchemy URL; `postgres://` ok    |
| `ASSET_STORAGE` | `disk`                           | `db` stores photo bytes in the database |
| `STORAGE_ROOT`  | `storage`                        | Only used in `disk` mode                |
| `SECRET_KEY`    | dev value                        | Set a real secret in production         |
| `ACCESS_TOKEN_MINUTES` | `1440`                    | Sign-in lifetime                        |
