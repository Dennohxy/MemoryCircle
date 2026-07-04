# Codex Prompt: Build the Memory Circle MVP

You are acting as a senior full-stack engineer, product-minded architect, QA lead, and documentation engineer. Build the MVP for **Memory Circle**, a collaborative digital memory-album platform.

## Product summary

Memory Circle is a cross-platform collaborative digital album for families and communities. Members contribute photos and stories from phones, PCs, or existing storage locations. Trusted users approve or edit submissions. Approved memories display as a classic tap-to-flip album on desktop, mobile, tablet, and TV-connected screens.

The MVP should not try to replace Google Photos, iCloud, OneDrive, or local folders. It should sit above existing storage and provide the memory layer: contribution, captions, approval, album layout, and flip display.

## Non-negotiable MVP principles

1. Story over storage.
2. Curation over dumping photos.
3. Display over file management.
4. Storage-agnostic by design.
5. Local cache for smooth viewing.
6. Roles and approvals from the beginning.
7. Simple templates before advanced graphics.
8. No hard dependency on one cloud provider.
9. Clear separation between photo source, cached asset, memory item, and album page.
10. Build a working vertical slice before adding advanced sync or peer recovery.

## Recommended stack

Use this stack unless the existing repository already dictates otherwise:

- Frontend app: Flutter
- Backend: FastAPI or NestJS
- Database: PostgreSQL
- Local cache/database: SQLite
- Object/display storage for MVP: local backend storage or S3-compatible storage
- Authentication: email/password for MVP
- Sync: REST first, WebSocket later
- Image processing: server-side thumbnail/display copy generation
- Album layout format: JSON
- Testing: unit tests, API tests, UI smoke tests

If starting from an empty repository, create a monorepo:

```text
memory-circle/
  apps/
    mobile_desktop_flutter/
  backend/
    api/
  docs/
  video/
  scripts/
  infra/
```

## Core MVP user stories

### Account and circle

- As a user, I can register and log in.
- As a user, I can create a Memory Circle.
- As a circle owner, I can invite members.
- As a circle owner, I can assign roles: owner, approver, contributor, viewer.

### Contribution

- As a contributor, I can add a memory by selecting a photo from device storage or uploading a file.
- As a contributor, I can add a caption, story, event name, date, and optional people/location metadata.
- As a contributor, I can submit the memory for approval.

### Approval

- As an approver, I can view pending memories.
- As an approver, I can approve, edit-and-approve, request changes, or reject.
- As a viewer, I only see approved memories.

### Album display

- As a user, I can open a Memory Circle album.
- As a user, I can view approved memories in classic flip-album mode.
- On desktop, show a two-page spread where possible.
- On mobile, show a single-page tap/swipe experience.
- Tap/click right side goes forward; tap/click left side goes backward.
- Fullscreen display mode must be supported on desktop.

### Storage behavior

- The MVP should store thumbnails and display-resolution copies for smooth album viewing.
- It should preserve a source reference that records where the photo came from.
- It should not require users to migrate all originals into Memory Circle.
- Full original archive and peer recovery should be designed but not fully implemented in MVP.

## MVP data model

Implement equivalent entities. Naming can vary, but the conceptual boundaries must remain.

### User

Fields:

- id
- display_name
- email
- password_hash
- created_at
- updated_at

### MemoryCircle

Fields:

- id
- name
- description
- owner_user_id
- default_approval_required
- created_at
- updated_at

### CircleMember

Fields:

- id
- circle_id
- user_id
- role: owner | approver | contributor | viewer
- status: invited | active | removed
- invited_by
- created_at
- updated_at

### PhotoSource

Fields:

- id
- user_id
- source_type: local_upload | local_folder | phone_gallery | google_drive | google_photos | icloud | onedrive | external_drive | nas | app_cache
- source_name
- connection_status
- permission_scope
- created_at
- last_checked_at

For the MVP, implement `local_upload` and `phone_gallery/local device upload` first. Keep the model ready for Google Drive, iCloud, and OneDrive connectors.

### PhotoAsset

Fields:

- id
- circle_id
- source_id
- source_type
- source_reference
- content_hash
- original_filename
- mime_type
- file_size
- width
- height
- capture_date
- thumbnail_path
- display_path
- cache_status: none | thumbnail | display_copy | original
- availability_status: available | missing | permission_lost | deleted_at_source
- created_by
- created_at
- updated_at

### MemoryItem

Fields:

- id
- circle_id
- asset_id
- caption
- story
- event_name
- memory_date
- location_text
- people_json
- submitted_by
- approval_status: draft | pending | approved | changes_requested | rejected
- approved_by
- approved_at
- created_at
- updated_at

### Album

Fields:

- id
- circle_id
- title
- description
- template_key
- created_by
- created_at
- updated_at

### AlbumPage

Fields:

- id
- album_id
- page_number
- layout_json
- version
- approval_status
- created_at
- updated_at

### ActivityLog

Fields:

- id
- circle_id
- actor_user_id
- action_type
- target_type
- target_id
- details_json
- created_at

## API requirements

Create REST endpoints equivalent to:

```text
POST   /auth/register
POST   /auth/login
GET    /me

POST   /circles
GET    /circles
GET    /circles/{circle_id}
PATCH  /circles/{circle_id}

POST   /circles/{circle_id}/invites
GET    /circles/{circle_id}/members
PATCH  /circles/{circle_id}/members/{member_id}

POST   /circles/{circle_id}/memories
GET    /circles/{circle_id}/memories?status=approved|pending|rejected
GET    /circles/{circle_id}/memories/{memory_id}
PATCH  /circles/{circle_id}/memories/{memory_id}
POST   /circles/{circle_id}/memories/{memory_id}/submit
POST   /circles/{circle_id}/memories/{memory_id}/approve
POST   /circles/{circle_id}/memories/{memory_id}/reject
POST   /circles/{circle_id}/memories/{memory_id}/request-changes

POST   /circles/{circle_id}/assets/upload
GET    /circles/{circle_id}/assets/{asset_id}/thumbnail
GET    /circles/{circle_id}/assets/{asset_id}/display

POST   /circles/{circle_id}/albums
GET    /circles/{circle_id}/albums
GET    /circles/{circle_id}/albums/{album_id}
POST   /circles/{circle_id}/albums/{album_id}/pages/generate
PATCH  /circles/{circle_id}/albums/{album_id}/pages/{page_id}

GET    /circles/{circle_id}/activity
GET    /circles/{circle_id}/health
```

## Frontend screens

Implement these screens first:

1. Login / Register
2. My Memory Circles
3. Create Memory Circle
4. Circle Dashboard
5. Add Memory
6. Pending Approval
7. Memory Detail / Approval Review
8. Album List
9. Flip Album Display
10. Members and Roles
11. Archive/Album Health placeholder
12. Settings placeholder

## Flip album behavior

The flip view is the MVP differentiator. Implement it even if the first animation is simple.

Desktop:

- Two-page spread when screen width permits.
- Fullscreen option.
- Right click/tap or right arrow: next.
- Left click/tap or left arrow: previous.
- Spacebar: next.
- Escape: exit fullscreen.

Mobile:

- Single-page layout.
- Swipe left/right.
- Tap right side: next.
- Tap left side: previous.

The display should prioritize readability, emotion, and simplicity.

## Album generation rules for MVP

When generating pages from approved memories:

- Use chronological order by memory_date where available.
- If no date exists, use approval date.
- Use simple templates:
  - one-photo feature page
  - two-photo story page
  - four-photo grid page
  - event title page
- Always display caption.
- Display story only when space allows; otherwise show preview and allow opening detail.

## Security requirements

- Passwords must be hashed.
- Role-based access must be enforced server-side.
- Viewers cannot approve or edit.
- Contributors cannot approve their own memory unless they are also approvers.
- All write actions should produce ActivityLog records.
- Uploaded files must be type-checked.
- Avoid exposing raw server paths.
- Use signed or authenticated URLs for image retrieval.

## Testing requirements

Implement tests for:

- Registration/login.
- Circle creation.
- Member role authorization.
- Memory creation.
- Pending-to-approved workflow.
- Rejection workflow.
- Asset upload and thumbnail generation.
- Album page generation.
- Flip view smoke test.

## Documentation requirements

Create or update:

```text
docs/README.md
docs/ARCHITECTURE.md
docs/API.md
docs/DATA_MODEL.md
docs/MVP_SCOPE.md
docs/ROADMAP.md
docs/SECURITY.md
docs/TESTING.md
docs/VIDEO_STORYBOARD.md
```

## Implementation order

Follow this order strictly:

1. Scaffold monorepo.
2. Build backend models and migrations.
3. Implement auth.
4. Implement circles and roles.
5. Implement asset upload and thumbnail/display generation.
6. Implement memory contribution workflow.
7. Implement approval workflow.
8. Implement album generation.
9. Implement Flutter screens.
10. Implement flip album display.
11. Add tests.
12. Add seed/demo data.
13. Write setup instructions.
14. Run lint/tests.
15. Produce a concise final implementation report.

## Demo seed data

Create demo data for:

- Circle: Otieno Family Memories
- Users: Owner, Approver, Contributor, Viewer
- 8 sample memories
- 1 pending memory
- 1 rejected memory
- 1 generated album called Family Highlights

Use placeholder images if no real images are provided.

## Definition of done

The MVP is done when:

- A new user can register.
- A user can create a Memory Circle.
- A second user can be invited or simulated as a member.
- A contributor can upload a photo and story.
- An approver can approve it.
- Approved memories appear in a flip album.
- The album can be viewed on desktop and mobile layouts.
- Roles are enforced.
- Tests pass.
- Documentation explains setup and architecture.

## Important exclusions for MVP

Do not implement yet unless the base MVP is complete:

- Full peer-to-peer sync.
- Google Drive/iCloud/OneDrive live connectors.
- AI clustering.
- Advanced graphics editor.
- Full CRDT collaborative editing.
- Payment/subscriptions.
- Public sharing marketplace.
- Native TV app.

Leave extension points for these features.

## Final response expected from Codex

When complete, report:

1. Files created/modified.
2. How to run backend.
3. How to run frontend.
4. How to run tests.
5. Known limitations.
6. Next recommended tasks.
