# Architecture

The MVP is a monorepo:

- `backend/api`: FastAPI REST API, SQLAlchemy models, local display asset storage.
- `apps/mobile_desktop_flutter`: Flutter client source for desktop/mobile/tablet layouts.
- `docs`: product, API, data, security, and testing notes.
- `infra`: optional PostgreSQL service for local development.

The backend separates photo source metadata, generated cached assets, memory items, album pages, and activity logs. SQLite is the default for quick local demos; `DATABASE_URL` can point at PostgreSQL.

Image originals are not exposed. The API creates thumbnail and display-resolution copies and serves those through authenticated endpoints.
