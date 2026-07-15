# Agent Handoff Log

Use this log for short handoffs between human maintainers, Codex, and Claude.
Newest entry goes at the top.

## 2026-07-16 - Claude (yearbook pilot backend complete)

Branch: `perf/image-loading`, deployed to `main` @ `2550c5d`.

Owner: Claude (completed the in-progress backend started per
`docs/GRADUATION_YEARBOOK_DESIGN.md`; models/endpoints were partially built,
I added the yearbook generation, member brand-asset route, composer refactor
(`compose_photo_entry_pages`), and the end-to-end pilot test).

Backend is now pilot-complete: theme presets + brand assets, campaign studio
APIs, contributor identity + consent, six contribution types with consensus
moderation, per-campaign quotas, campaign-scoped galleries, and deterministic
themed yearbook generation (`POST /circles/{id}/campaigns/{id}/yearbook`,
schema_version-2 pages with immutable theme snapshots, revision bump on
regenerate). 37 backend tests pass.

Remaining for the pilot (Flutter, unclaimed):

1. Themed renderer: `album_page_view.dart` needs a schema_version-2 branch
   for templates graduation_cover, official_message, graduate_profile_single/
   _pair, photo_mosaic (reuse mosaic rows), dedication_grid,
   typed_signature_grid, acknowledgements, graduation_back_cover. Theme tokens
   ride inside each page's layout_json ("theme").
2. Guest structured forms in `guest_campaign_screen.dart`: consent step, type
   picker, profile/dedication/signature forms against
   `GET /campaigns/{token}` -> `contribution_schema`, contributor endpoints
   (`/contributors`, `/contributors/verify`, `/contribution-assets`,
   `/contributions` CRUD + withdraw).
3. Owner studio in `campaigns_screen.dart`: create-from-preset, details,
   branding upload (kind + rights_confirmed multipart), publish preflight
   (`validation.errors`), moderation list + approve/reject/request-changes,
   and a "Generate yearbook" action.

Checks run: backend pytest (37), py_compile, flutter analyze + test at
`2550c5d` in a clean worktree.

Known risks: startup `ALTER TABLE` migration (design doc prefers Alembic —
deferred); share packages don't yet rewrite v2 page asset URLs for public
viewing (public yearbook shares are Phase 4).

## 2026-07-08 - Claude (circle merge + inactivity)

Branch: `feature/circle-merge-and-inactivity` (cut from `main` @ `521f4d6`)

Owner: Claude

Intent: Founder's final asks for the day — merge two circles, and an
inactivity lifecycle for members.

Delivered:
- **Merge circles** (approval-gated, mirrors album-removal). Source owner
  requests a merge into a target; target owner accepts. On accept, photos
  (deduped by content hash), memories, albums, and members move to the
  target (shared member keeps higher role); source circle is archived
  (`status=archived`, hidden from `/circles` and search). New
  `CircleMergeRequest` model + `ensure_circle_merge_support()` backfill.
- **Member inactivity** from the activity log (owner exempt): >=30 idle
  days auto-demotes one role step; >=90 idle days flags for owner removal.
  `GET /circles/{id}/members` runs the sweep for owners and returns
  `last_active_at` + `inactivity_tier`; `POST .../members/apply-inactivity`
  is cron-ready. Removal reuses `PATCH member status=removed`.
- Flutter: merge initiation + incoming-merge cards and an inactive-member
  section with Remove, all in `members_screen.dart`; API/model support in
  `api_client.dart` / `models.dart`.

Files (committed): `backend/api/app/{main,models}.py`,
`backend/api/tests/test_mvp.py`, `apps/.../lib/api/{api_client,models}.dart`,
`apps/.../lib/screens/members_screen.dart`, `docs/API.md`.

Checks: `pytest` 26 passed; `py_compile` OK; `flutter analyze lib/api
lib/screens/members_screen.dart` clean.

Known risks / COLLISION:
- Codex has an **uncommitted in-flight i18n effort** in the working tree:
  untracked `apps/.../lib/i18n/` (currently has compile errors in
  `index.dart`) plus uncommitted edits to `circles_screen.dart`,
  `memory_circle_app.dart`, `auth_screen.dart`, `settings_screen.dart`,
  `app_shell.dart`, `error_state.dart`, `loading_state.dart`,
  `circle_dashboard_screen.dart`. I did **not** touch or commit any of
  those — my commit contains only the 6 files above. A whole-project
  `flutter analyze` will fail until Codex finishes i18n; my files analyze
  clean in isolation.
- Merge does not yet surface an owner-facing "this circle was archived"
  view for the source; source members are notified via the notification
  queue only.

Next recommended step:
- Codex: finish/commit i18n, then a whole-project `flutter analyze`.
- Do not push `main` (deploys omoidenowa.com) without founder approval.

## 2026-07-08 - Claude

Branch: `feature/album-edit-and-add-photos`

Owner: Claude

Intent: Apply the founder's decisions on Codex's open questions and land the
pre-30-day feature set. Founder decisions (2026-07-08):

1. Album size: no limit on proposals; album maximum and default is
   **12 photos x active circle members**, computed dynamically.
2. Photo approval voting group: **owners + approvers only** (viewers and
   contributors do not vote and cannot stall albums).
3. Cover/sequence stays reviewer-only, as Codex built it.

Files/areas touched:

- `backend/api/app/main.py` - `approval_member_ids()` (reviewer voting
  group), `album_photo_cap()` (12 x members), cap validation on album
  create/patch, effective target + `max_photo_count` in `serialize_album`,
  non-reviewer votes no longer recorded, approve endpoint now 403s
  non-reviewers.
- `backend/api/app/models.py` - `Album.target_photo_count` nullable
  (NULL = family maximum).
- `backend/api/tests/test_mvp.py` - reviewer-only consensus tests, new
  12-per-member cap test.
- Flutter: `photos_screen.dart` (reviewer wording, approve button hidden
  from non-reviewers), `albums_screen.dart` (optional photo count with
  family-maximum helper), `models.dart` / `api_client.dart`
  (`max_photo_count`), `app_shell.dart` (role passed to PhotosView).
- Docs: `ALBUM_PHOTO_COUNT_PLAN.md` (decision recorded), `API.md`.

Committed Codex's 2026-07-08 feature work first (commit
"Add all-photos view, consensus approval, cover/order controls, face-safe
layouts") so authorship stays traceable, EXCLUDING the in-flight FCM client
wiring (`firebase.json`, `lib/firebase_options.dart`,
`lib/app/push_notifications.dart`, `web/firebase-messaging-sw.js`,
`docs/PUSH_NOTIFICATIONS.md`, `pubspec.yaml`/`.lock`,
`lib/app/memory_circle_app.dart`) - Codex was actively editing those while
this work happened. Codex: commit your Firebase work on top when ready.

Checks run:

- `.venv/bin/python -m pytest` from `backend/api` (18 passed)
- `python3 -m py_compile app/main.py app/models.py app/seed.py`
- `dart format lib`
- `flutter analyze` (no issues)

Known risks:

- Existing databases keep any stored `target_photo_count` (e.g. 24 from the
  earlier default); the 12-per-member cap is enforced at generation time via
  `min(target, cap)`.
- `voter_ids` recorded before this change may include non-reviewers; the
  unanimity check and progress counts handle this correctly.
- Not pushed: `scripts/repo_publish.sh` requires a clean tree and Codex's
  Firebase work is still uncommitted.

Next recommended step:

- Codex finishes and commits FCM wiring, then publish the branch.

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
