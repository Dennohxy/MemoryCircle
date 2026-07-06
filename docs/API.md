# API

Base URL: `http://127.0.0.1:8000`

Authentication uses bearer tokens returned by:

- `POST /auth/register`
- `POST /auth/login`
- `GET /me`

Circle and role endpoints:

- `POST /circles`
- `GET /circles`
- `GET /circles/{circle_id}`
- `PATCH /circles/{circle_id}`
- `POST /circles/{circle_id}/invites`
- `GET /circles/{circle_id}/members`
- `PATCH /circles/{circle_id}/members/{member_id}`

Assets and memories:

- `POST /circles/{circle_id}/assets/upload` (re-uploading identical bytes returns the existing asset)
- `POST /circles/{circle_id}/assets/match` (body `{"hashes": [sha256...]}` → `{"matches": {hash: asset}}`)
- `GET /circles/{circle_id}/assets/{asset_id}/thumbnail`
- `GET /circles/{circle_id}/assets/{asset_id}/display`
- `POST /circles/{circle_id}/memories`
- `GET /circles/{circle_id}/memories?status=approved|pending|rejected`
- `GET /circles/{circle_id}/memories/{memory_id}`
- `PATCH /circles/{circle_id}/memories/{memory_id}`
- `POST /circles/{circle_id}/memories/{memory_id}/submit`
- `POST /circles/{circle_id}/memories/{memory_id}/approve`
- `POST /circles/{circle_id}/memories/{memory_id}/reject`
- `POST /circles/{circle_id}/memories/{memory_id}/request-changes`

Albums:

- `POST /circles/{circle_id}/albums`
- `GET /circles/{circle_id}/albums`
- `GET /circles/{circle_id}/albums/{album_id}`
- `PATCH /circles/{circle_id}/albums/{album_id}` (title/description; owner or reviewer)
- `POST /circles/{circle_id}/albums/{album_id}/retire` (request removal; owner/reviewer)
- `POST /circles/{circle_id}/albums/{album_id}/retire/approve` (approve a pending removal)
- `POST /circles/{circle_id}/albums/{album_id}/retire/cancel` (keep the album)
- `POST /circles/{circle_id}/albums/{album_id}/pages/generate`
- `PATCH /circles/{circle_id}/albums/{album_id}/pages/{page_id}`

Operations:

- `GET /circles/{circle_id}/activity`
- `GET /circles/{circle_id}/health`
- `GET /health`
