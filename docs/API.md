# API

Base URL: `http://127.0.0.1:8000`

Authentication uses bearer tokens returned by:

- `POST /auth/register`
- `POST /auth/login`
- `GET /me`
- `POST /me/notification-subscriptions`
- `GET /me/notifications`
- `POST /me/notifications/{notification_id}/read`

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
- `GET /circles/{circle_id}/photos` (all uploaded photos outside album layout context)
- `POST /circles/{circle_id}/photos/send-for-approval` (moves draft/unapproved photos into the current circle's approval queue and queues member notifications)
- `POST /circles/{circle_id}/memories`
- `GET /circles/{circle_id}/memories?status=approved|pending|rejected`
- `GET /circles/{circle_id}/memories/{memory_id}`
- `PATCH /circles/{circle_id}/memories/{memory_id}`
- `POST /circles/{circle_id}/memories/{memory_id}/submit`
- `POST /circles/{circle_id}/memories/{memory_id}/approve`
- `POST /circles/{circle_id}/memories/{memory_id}/reject`
- `POST /circles/{circle_id}/memories/{memory_id}/request-changes`

Photo approval is consensus-based. A submitted memory stays `pending` until
every active circle member has approved it. The approve endpoint records the
current member's approval vote; it does not let the owner or reviewer override
the rest of the circle. Memory responses include an `approval` object with
`approvals_have`, `approvals_needed`, and `voter_ids`.

When an uploaded image has a source capture date in image metadata, the backend
stores it on the asset and uses it as the memory date if the contributor did
not enter a date. Album generation uses manual `memory_sequence` first; without
manual order, memories are ordered by memory/source date before approval time.

Approval notifications are queued as `photo_approval_needed` notifications for
members who have not yet approved a pending memory. The current implementation
stores notification subscriptions and notification records; mobile/web push
providers can deliver from that queue.

Albums:

- `POST /circles/{circle_id}/albums` (supports `target_photo_count`, `cover_memory_id`, and `memory_sequence`)
- `GET /circles/{circle_id}/albums`
- `GET /circles/{circle_id}/albums/{album_id}`
- `PATCH /circles/{circle_id}/albums/{album_id}` (title, description, target count, cover, sequence; owner or reviewer)
- `POST /circles/{circle_id}/albums/{album_id}/retire` (request removal; owner/reviewer)
- `POST /circles/{circle_id}/albums/{album_id}/retire/approve` (approve a pending removal)
- `POST /circles/{circle_id}/albums/{album_id}/retire/cancel` (keep the album)
- `POST /circles/{circle_id}/albums/{album_id}/pages/generate`
- `PATCH /circles/{circle_id}/albums/{album_id}/pages/{page_id}`

Operations:

- `GET /circles/{circle_id}/activity`
- `GET /circles/{circle_id}/health`
- `GET /health`
