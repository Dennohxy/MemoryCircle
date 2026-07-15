# Omoide no Wa MVP

Omoide no Wa is a collaborative digital memory album for families and communities: a private Memory Circle for shared photos, collective approvals, and beautifully kept albums.

## Structure

```text
apps/mobile_desktop_flutter/  Flutter app source
backend/api/                  FastAPI backend and tests
docs/                         Architecture, API, data, security, testing
infra/                        Optional local PostgreSQL
scripts/                      Development helpers
video/                        Reserved for video assets
```

## Co-Managed Flow

This repo is co-managed by human maintainers, Codex, and Claude. Use
[docs/CO_MANAGEMENT.md](docs/CO_MANAGEMENT.md) as the shared workflow.

Before starting work:

```bash
./scripts/repo_sync.sh
```

Before handing off or opening a PR:

```bash
./scripts/repo_publish.sh
```

## Run Backend

```bash
cd backend/api
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r requirements.txt
python3 -m uvicorn app.main:app --reload
```

Open `http://127.0.0.1:8000/docs` for interactive API docs.

## Seed Demo Data

```bash
cd backend/api
source .venv/bin/activate
python3 -m app.seed
```

Demo users use password `Password123!`:

- `owner@example.com`
- `editor@example.com`
- `approver@example.com`
- `contributor@example.com`
- `viewer@example.com`

## Run Frontend

Flutter is not vendored in this repo. When Flutter is installed:

```bash
cd apps/mobile_desktop_flutter
flutter pub get
flutter run -d chrome --dart-define=API_BASE=http://127.0.0.1:8000
```

The Flutter app is organized as:

```text
lib/
  main.dart                 Entry point
  app/                      App root and theme tokens
  api/                      API client and typed models
  screens/                  Auth, circles, dashboard, add memory,
                            review, albums, flip album, members,
                            health, settings
  widgets/                  Shared shell, cards, states, album pages
```

It renders on phones (top app bar plus screen stack) and on
tablet/desktop (navigation rail with a two-page album spread).
Protected photos are fetched with the bearer token and displayed via
`Image.memory`, so no extra setup is needed for thumbnails.

## Run Tests

```bash
cd backend/api
source .venv/bin/activate
python3 -m pytest
```

When Flutter is installed:

```bash
cd apps/mobile_desktop_flutter
flutter test
```
