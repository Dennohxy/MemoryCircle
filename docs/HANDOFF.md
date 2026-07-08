# Agent Handoff Log

Use this log for short handoffs between human maintainers, Codex, and Claude.
Newest entry goes at the top.

## 2026-07-08 - Codex

Branch: `feature/album-edit-and-add-photos`

Latest follow-up:

- Added FCM provider wiring:
  - Flutter dependencies `firebase_core` and `firebase_messaging`.
  - Push token registration after sign-in/restore.
  - Web service worker placeholder at `web/firebase-messaging-sw.js`.
  - Backend dependency `firebase-admin`.
  - Backend provider delivery helper in `app/notifications.py`.
  - Setup docs in `docs/PUSH_NOTIFICATIONS.md`.
- Added current-circle `POST /circles/{circle_id}/photos/send-for-approval`
  to move draft/unapproved photos into pending approval and queue member
  notifications.
- Added notification subscriptions and unread notification APIs.
- Added source capture-date extraction from image metadata, and memory dates now
  inherit source dates when no user date is provided.
- Album generation uses member-chosen order first; otherwise it orders by
  memory/source date before approval time.
- Bulk add no longer auto-approves reviewer uploads; it sends them for family
  approval and queues notifications.

Checks run:

- `/tmp/memorycircle-pytest-venv/bin/python -m pytest` from `backend/api`
- `python3 -m py_compile app/main.py app/models.py app/seed.py`
- `dart format lib`
- `flutter analyze`

## 2026-07-08 - Codex

Branch: `feature/album-edit-and-add-photos`

Latest commit at start: `1c78ca9 Add approval-gated album removal`

Owner: Codex

Intent: Continue Claude's requested pre-30-day-plan work: standalone uploaded
photo visibility, all-member photo approval, album cover/order controls, target
photo count planning, and face-safe album layouts.

Files/areas touched:

- `backend/api/app/main.py`
- `backend/api/app/models.py`
- `backend/api/app/seed.py`
- `backend/api/tests/test_mvp.py`
- `apps/mobile_desktop_flutter/lib/api/`
- `apps/mobile_desktop_flutter/lib/screens/photos_screen.dart`
- `apps/mobile_desktop_flutter/lib/screens/albums_screen.dart`
- `apps/mobile_desktop_flutter/lib/widgets/album_page_view.dart`
- `apps/mobile_desktop_flutter/lib/widgets/app_shell.dart`
- `docs/API.md`
- `docs/ALBUM_PHOTO_COUNT_PLAN.md`

Checks run:

- `/tmp/memorycircle-pytest-venv/bin/python -m pytest` from `backend/api`
- `python3 -m py_compile app/main.py app/models.py app/seed.py`
- `dart format lib`
- `flutter analyze`

Known risks:

- All active circle members, including viewers, must approve a photo before it
  enters the album. This matches the current request, but product may later
  choose a narrower voting group.
- `docs/ALBUM_PHOTO_COUNT_PLAN.md` still needs human approval for the default
  album size.
- `assets/` is still untracked from earlier work.

Next recommended step:

- Human/Claude should review the consensus approval UX wording and approve the
  default album target count.

## 2026-07-08 - Codex

Branch: `feature/album-edit-and-add-photos`

Latest commit at start: `1c78ca9 Add approval-gated album removal`

Owner: Codex

Intent: Add a shared co-management flow so Claude, Codex, and human
maintainers can work through one unified repository.

Files/areas touched:

- `README.md`
- `docs/README.md`
- `docs/CO_MANAGEMENT.md`
- `docs/HANDOFF.md`
- `scripts/repo_sync.sh`
- `scripts/repo_publish.sh`

Checks run:

- `bash -n scripts/repo_sync.sh`
- `bash -n scripts/repo_publish.sh`
- `./scripts/repo_sync.sh` was intentionally blocked by uncommitted tracked
  workflow changes.

Known risks:

- `assets/` is currently untracked. Commit only intentional source assets.

Next recommended step:

- Review the co-management flow, commit it, then publish the branch so Claude
  can pull the same protocol.

## Template

```text
Branch:
Latest commit:
Owner:
Intent:
Files/areas touched:
Checks run:
Known risks:
Next recommended step:
```
