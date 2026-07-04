# Memory Circle: Full Project Documentation

## 1. Executive summary

Memory Circle is a collaborative digital memory-album platform for families and communities. It lets members contribute photos and stories from phones, PCs, or existing storage locations such as Google Drive, iCloud, OneDrive, local folders, external drives, or network storage. Trusted members approve or edit submissions. Approved memories are displayed in a beautiful classic tap-to-flip album across PCs, smartphones, tablets, and living-room screens.

The product should not compete directly as a photo backup or cloud storage service. It should operate as a storage-agnostic memory layer above existing photo locations. Its value is in contribution, curation, storytelling, approval, design, display, and long-term memory organization.

## 2. Product positioning

### 2.1 Product category

Collaborative digital memory album.

### 2.2 Core promise

Everyone contributes. Trusted people curate. The album lives everywhere.

### 2.3 User-facing value proposition

Memory Circle turns scattered photos into living family and community albums. Members contribute memories from any device, approvers curate the story, and the final album displays beautifully on phones, PCs, tablets, and living-room screens.

### 2.4 What the product is not

Memory Circle is not primarily:

- A generic cloud storage platform.
- A Google Photos replacement.
- A file synchronization utility.
- A professional design suite.
- A social media network.

### 2.5 What the product is

Memory Circle is:

- A shared album workspace.
- A moderated memory contribution system.
- A storytelling and curation layer.
- A classic flip-album display interface.
- A storage-agnostic index over existing photo locations.
- A future-ready distributed archive platform.

## 3. Target users

### 3.1 Primary MVP segment

Families and diaspora families.

Typical examples:

- Families spread across Kenya, Japan, Europe, the United States, and other locations.
- Grandparents who want to see updated family memories without managing many apps.
- Parents collecting school, graduation, wedding, travel, and family-history memories.
- Families wanting one curated shared album rather than scattered photo dumps.

### 3.2 Secondary segments

- Alumni groups.
- Schools.
- Churches and community groups.
- Wedding/event groups.
- Elderly care homes.
- Local history groups.
- Corporate culture/memory walls.

## 4. Core product principles

1. Story over storage.
2. Curation over dumping photos.
3. Display over file management.
4. Simplicity over technical complexity.
5. Storage-agnostic by default.
6. Approval and trust from the start.
7. Templates before free-form design.
8. Local cache for performance and offline viewing.
9. Distributed archive as a phased enhancement, not an MVP blocker.
10. Emotional usefulness before infrastructure sophistication.

## 5. Main user journeys

### 5.1 Create a Memory Circle

A user creates a private Memory Circle, gives it a name, invites family or community members, and assigns roles.

### 5.2 Add a memory

A contributor selects a photo from their phone, PC, or connected storage. They add caption, story, date, event, location, and optional people tags. The memory is submitted for approval.

### 5.3 Approve and curate

An approver reviews the pending memory. They can approve, edit and approve, request changes, reject, or assign it to a specific album.

### 5.4 View flip album

Approved memories appear in a classic flip album. Desktop uses a two-page spread where possible. Mobile uses a single-page tap/swipe view.

### 5.5 Display mode

A PC, tablet, or TV-connected device can run fullscreen display mode with tap/click/keyboard navigation and optional auto-flip.

### 5.6 Archive and restore

In later phases, users can designate one or more full archive devices. A new device can rebuild the album from existing metadata and available archive devices.

## 6. Roles and permissions

| Role | Core permissions |
|---|---|
| Owner | Full control, invite/remove members, assign roles, manage settings, approve, archive, delete circle |
| Approver | Review, edit, approve, request changes, reject memories |
| Contributor | Add memories and submit for approval |
| Viewer | View approved albums only |
| Display device | Read-only album display mode |

Important rule: all permissions must be enforced server-side, not only in the app UI.

## 7. Storage-agnostic design

### 7.1 Storage principle

Memory Circle should not force users to move all photos into its own storage. It should work with photos wherever users keep them.

Supported or planned source types:

- Local PC folder.
- Smartphone gallery.
- Google Drive.
- Google Photos.
- iCloud.
- OneDrive.
- External hard drive.
- Network-attached storage.
- App-managed cache.
- Optional app cloud backup.

### 7.2 Storage modes

| Mode | Description | MVP status |
|---|---|---|
| Reference only | Store metadata and reference original source | Design now, partial MVP |
| Display cache | Store thumbnails and display-resolution copies | MVP default |
| Full local archive | Keep originals on chosen device | Version 2 |
| Optional cloud backup | Store full backup in app cloud | Paid/future version |

### 7.3 Photo identity

Every image should be identified by a content hash when possible.

Important metadata:

- Content hash.
- Source type.
- Source reference.
- File name.
- File size.
- MIME type.
- Width and height.
- Capture date.
- Thumbnail path.
- Display copy path.
- Availability status.

This allows duplicate detection, missing file detection, and future archive recovery.

## 8. MVP scope

### 8.1 Include in MVP

- User registration/login.
- Create Memory Circle.
- Invite or simulate members.
- Assign roles.
- Upload/select photos from local device.
- Generate thumbnail and display copy.
- Add caption/story/date/event/location.
- Submit memory for approval.
- Approve, edit-and-approve, reject, request changes.
- Create album from approved memories.
- Basic album templates.
- Flip album view.
- Desktop and mobile responsive layouts.
- Activity log.
- Basic album health placeholder.
- Documentation and seed/demo data.

### 8.2 Exclude from MVP

- Full peer-to-peer sync.
- Live Google Drive/iCloud/OneDrive connectors.
- AI clustering.
- Advanced graphics editor.
- Real-time collaborative page editing.
- Payments/subscriptions.
- Native TV app.
- Public marketplace.

## 9. System architecture

### 9.1 MVP architecture

The MVP uses a server-assisted architecture.

- Backend stores accounts, circles, roles, metadata, approval records, album layouts, thumbnails, and display copies.
- App stores local cache and interacts with backend APIs.
- Photo originals remain with the user unless explicitly uploaded or cached according to MVP behavior.

### 9.2 Future architecture

Later versions add:

- Device registration.
- Full local archive devices.
- Archive health scoring.
- Restore from another member device.
- Optional cloud backup.
- Cloud provider connectors.
- Advanced album design engine.

## 10. Recommended technical stack

| Layer | Recommendation |
|---|---|
| App | Flutter |
| Backend | FastAPI or NestJS |
| Database | PostgreSQL |
| Local cache | SQLite |
| MVP image storage | Backend local storage or S3-compatible storage |
| Authentication | Email/password, JWT/session |
| Sync | REST first, WebSocket later |
| Image processing | Server-side thumbnail/display generation |
| Layout format | JSON |
| Tests | API tests, unit tests, frontend smoke tests |

## 11. Data model

### 11.1 User

Represents a person with an account.

Fields:

- id
- display_name
- email
- password_hash
- created_at
- updated_at

### 11.2 MemoryCircle

Represents a shared memory group.

Fields:

- id
- name
- description
- owner_user_id
- default_approval_required
- created_at
- updated_at

### 11.3 CircleMember

Represents a user's membership and role in a Memory Circle.

Fields:

- id
- circle_id
- user_id
- role
- status
- invited_by
- created_at
- updated_at

### 11.4 PhotoSource

Represents where the photo came from.

Fields:

- id
- user_id
- source_type
- source_name
- connection_status
- permission_scope
- created_at
- last_checked_at

### 11.5 PhotoAsset

Represents an image asset known to Memory Circle.

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
- cache_status
- availability_status
- created_by
- created_at
- updated_at

### 11.6 MemoryItem

Represents a meaningful memory based on a photo and story.

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
- approval_status
- approved_by
- approved_at
- created_at
- updated_at

### 11.7 Album

Represents a curated collection of approved memories.

Fields:

- id
- circle_id
- title
- description
- template_key
- created_by
- created_at
- updated_at

### 11.8 AlbumPage

Represents an album page rendered by the flip display engine.

Fields:

- id
- album_id
- page_number
- layout_json
- version
- approval_status
- created_at
- updated_at

### 11.9 ActivityLog

Records important user actions.

Fields:

- id
- circle_id
- actor_user_id
- action_type
- target_type
- target_id
- details_json
- created_at

## 12. API design

Core API groups:

- Authentication.
- User profile.
- Memory Circles.
- Members and roles.
- Photo assets.
- Memory items.
- Approval actions.
- Albums and pages.
- Activity log.
- Album health.

The API should be role-aware and should never rely only on frontend restrictions.

## 13. Frontend design

### 13.1 Main screens

1. Login / Register.
2. My Memory Circles.
3. Create Memory Circle.
4. Circle Dashboard.
5. Add Memory.
6. Pending Approval.
7. Memory Review.
8. Album List.
9. Flip Album Display.
10. Members and Roles.
11. Album Health.
12. Settings.

### 13.2 Flip display requirements

Desktop:

- Two-page spread where possible.
- Fullscreen mode.
- Keyboard navigation.
- Click/tap left or right side to flip.

Mobile:

- Single-page view.
- Swipe navigation.
- Tap left/right to flip.

Visual style:

- Warm.
- Calm.
- Paper texture.
- Soft shadows.
- Classic album feel.
- Minimal controls in display mode.

## 14. Album layout system

Album pages should be stored as layout JSON, not flattened images.

A page layout includes:

- Background.
- Photo objects.
- Text objects.
- Position.
- Size.
- Rotation.
- Shape or mask.
- Frame style.
- Memory references.

MVP templates:

- Title page.
- One-photo feature page.
- Two-photo story page.
- Four-photo grid page.
- Event separator page.

## 15. Security and privacy

Required MVP controls:

- Password hashing.
- Server-side role enforcement.
- Authenticated asset access.
- File type validation.
- Activity logs.
- Soft-delete behavior where possible.
- No exposure of raw server file paths.
- Privacy-by-default circle settings.

Future controls:

- Per-circle encryption.
- Device authorization.
- Device revocation.
- Local app lock.
- Optional two-factor authentication.
- Encrypted cloud backup.

## 16. Testing plan

### 16.1 Backend tests

- Register/login.
- Protected endpoint access.
- Circle creation.
- Role authorization.
- Asset upload.
- Thumbnail generation.
- Memory creation.
- Approval workflow.
- Album page generation.

### 16.2 Frontend tests

- Login smoke test.
- Circle list load.
- Add memory flow.
- Approval flow.
- Album view load.
- Flip navigation.

### 16.3 Manual test script

1. Register owner.
2. Create Memory Circle.
3. Add contributor and approver.
4. Contributor uploads memory.
5. Approver approves memory.
6. Owner generates album.
7. Viewer opens flip album.
8. Desktop fullscreen mode works.
9. Mobile layout works.

## 17. Roadmap

### Version 0.1: Clickable prototype

- Static UI prototype.
- Flip album mockup.
- Add-memory mockup.
- Approval mockup.

### Version 0.2: Working MVP

- Auth.
- Circles.
- Uploads.
- Memories.
- Approval.
- Basic albums.
- Flip display.

### Version 0.3: Family beta

- 5-20 test families.
- Desktop display mode.
- Mobile contribution.
- Activity notifications.
- Archive export.

### Version 0.4: Archive resilience

- Device registration.
- Full archive device designation.
- Album safety score.
- Restore from archive device.

### Version 1.0: Paid family release

- Polished UI.
- Stable sync.
- Multiple circles.
- Better templates.
- Export tools.
- Family subscription.

### Version 2.0: Community/institution release

- Larger circles.
- Admin dashboard.
- Moderation queue.
- School/church/alumni templates.
- Public/private albums.
- PDF/photo-book export.

## 18. Business model

### 18.1 Freemium family plan

| Tier | Target | Features |
|---|---|---|
| Free | Trial families | 1 circle, limited members, limited display storage |
| Family Plus | Families/diaspora | More members, albums, display mode, export |
| Family Archive | Serious family archive | Full backup, archive health, restore tools |
| Community | Churches, alumni, schools | Larger groups, roles, approval queues |
| Institution | Organizations | Branding, dashboards, support |

### 18.2 What to charge for

Charge for:

- Collaboration.
- Album experience.
- Approval and moderation.
- Display mode.
- Archive protection.
- Group administration.
- Export/photo-book features.

Avoid charging mainly as raw storage in the early phase.

## 19. MVP success metrics

- Number of Memory Circles created.
- Invited members per circle.
- Memories submitted per week.
- Memories approved per week.
- Flip album views.
- Desktop display hours.
- Captions/stories per memory.
- Return visits by viewers.
- Archive exports.
- Paid conversion after beta.

## 20. Video concept

The MVP promo video should emphasize:

- Photos are everywhere.
- Stories are scattered.
- Memory Circle connects existing photo sources.
- Members contribute photos and stories.
- Trusted people approve and curate.
- The result displays as a beautiful flip album.
- The product is designed for families and communities.

Recommended length: 60-90 seconds.

## 21. Codex development instructions

Codex should build the MVP in this order:

1. Scaffold repository.
2. Backend models and migrations.
3. Authentication.
4. Circles and roles.
5. Asset upload and display copy generation.
6. Memory contribution workflow.
7. Approval workflow.
8. Album generation.
9. Flutter screens.
10. Flip album display.
11. Tests.
12. Seed/demo data.
13. Documentation.
14. Final implementation report.

## 22. Definition of done

The MVP is done when:

- A user can register and log in.
- A user can create a Memory Circle.
- Members can be invited or simulated.
- A contributor can upload a photo and story.
- An approver can approve it.
- Approved memories appear in a flip album.
- The album works in desktop and mobile layouts.
- Roles are enforced.
- Tests pass.
- Documentation is complete.

## 23. Final product statement

Memory Circle is a storage-agnostic collaborative memory-album platform. It turns scattered photos from phones, PCs, cloud drives, and archives into curated shared albums. Members contribute photos and stories, trusted users approve and edit them, and the final result displays as a classic tap-to-flip album across personal and shared devices.
