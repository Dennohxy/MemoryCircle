# Claude Prompt: Redesign and Modernize Memory Circle

You are Claude, acting as a senior Flutter product designer, frontend architect, and UX engineer. Redesign and modernize the **Memory Circle** MVP app in this repository while preserving the working backend contract.

## Project Context

Memory Circle is a collaborative digital memory-album platform for families and communities.

Core product idea:

- Members contribute photos and stories.
- Trusted users approve or reject submissions.
- Approved memories become a curated flip-style family album.
- The product is not a generic photo dump or cloud storage replacement. It is a storytelling, curation, and display layer.

The current repository is a monorepo:

```text
/Volumes/HD-PGF-A/MemoryCircle
  apps/mobile_desktop_flutter/   Flutter MVP app
  backend/api/                   FastAPI backend
  docs/                          Product/API/security/testing docs
  scripts/                       Backend launch and seed helpers
```

Read these first:

```text
README.md
docs/ARCHITECTURE.md
docs/API.md
docs/MVP_SCOPE.md
docs/SECURITY.md
apps/mobile_desktop_flutter/lib/main.dart
apps/mobile_desktop_flutter/pubspec.yaml
```

## Current State

The backend is functional and should be treated as the source of truth for API behavior.

The Flutter app currently exists mostly in one file:

```text
apps/mobile_desktop_flutter/lib/main.dart
```

It has basic screens for:

- Login/register
- Circle list
- Circle dashboard
- Add memory
- Pending approval
- Albums
- Flip album
- Members
- Placeholder health/settings

The UI is MVP-simple and needs a serious redesign and modernization pass.

## Goal

Transform the Flutter app from a prototype into a polished, modern, emotionally warm MVP experience that feels credible for families, diaspora communities, and memory curation.

Do **not** redesign the backend unless a small API client adjustment is needed. Keep backend endpoint paths and payload assumptions compatible with the current FastAPI API.

Most importantly: design this for non-technical family members. A grandparent, parent, auntie, uncle, or community organizer should understand what to do without reading documentation. The app should guide people gently, use everyday language, and avoid technical concepts such as assets, cache, payloads, IDs, API responses, approval statuses, or storage references in the user interface.

## Product Design Direction

The app should feel:

- Warm, calm, trustworthy, and family-centered.
- Modern but not sterile.
- More like a curated album workspace than an admin dashboard.
- Clear enough for non-technical family members.
- Elegant on desktop, tablet, and mobile.
- Simple enough that a first-time user can log in, add a photo/story, review a memory, and open the album without help.
- Forgiving: clear progress, obvious next steps, readable errors, and no dead ends.

Avoid:

- Generic SaaS dashboard visuals.
- Purple/blue gradient-heavy startup styling.
- Overly beige monotone styling.
- Marketing landing-page filler.
- Huge explanatory blocks of in-app text.
- Nested cards and decorative clutter.
- UI that looks like a database admin panel.
- Technical labels such as asset, source, cache, payload, endpoint, status code, JSON, or ID in normal user-facing UI.
- Dense grids of actions that make users decide what the app means before they can use it.

Preferred visual language:

- Clean Material 3 foundation.
- Soft paper-inspired surfaces.
- Muted but varied palette: warm ivory, deep green, ink, soft coral/rust accents, subtle gold.
- Strong photo-first layout.
- Tactile album feel in the flip view.
- Consistent spacing, readable typography, and graceful empty/loading/error states.

## Required Redesign Scope

### 1. Refactor Flutter Structure

Break the current single-file app into maintainable files. Suggested structure:

```text
lib/
  main.dart
  app/
    memory_circle_app.dart
    theme.dart
  api/
    api_client.dart
    models.dart
  screens/
    auth_screen.dart
    circles_screen.dart
    circle_dashboard_screen.dart
    add_memory_screen.dart
    memories_review_screen.dart
    albums_screen.dart
    flip_album_screen.dart
    members_screen.dart
    placeholder_screen.dart
  widgets/
    app_shell.dart
    circle_card.dart
    memory_card.dart
    album_page_view.dart
    empty_state.dart
    loading_state.dart
    error_state.dart
```

You may choose a different structure if it is clean and idiomatic.

### 2. Modernize Navigation and Layout

Implement responsive navigation:

- Mobile: top app bar plus simple screen stack.
- Tablet/desktop: a quiet navigation rail or side panel where appropriate.
- Preserve simple routes and keep code easy to understand.
- Use human-centered labels: “My Albums”, “Add a Memory”, “Review Memories”, “Family Members”, “Album Health”.
- Make the most common next action obvious on each screen.
- Avoid exposing implementation concepts in navigation.

Make major screens responsive:

- Desktop should use available width without stretching text awkwardly.
- Mobile should remain one-handed and readable.
- Use stable constraints and avoid layout jumps.

### 3. Redesign Login/Register

Create a polished auth screen:

- Brand-forward: “Memory Circle”.
- Warm short supporting line.
- Toggle between login and create account.
- Clear error and loading states.
- Keep demo credentials convenient without making the screen feel fake.
- Use plain helper text such as “Sign in to open your family albums.”
- Error messages should explain what the user can do next, not just what failed.

### 4. Redesign My Memory Circles

Replace plain list tiles with thoughtful circle cards:

- Circle name and description.
- Subtle metadata if available.
- Primary action to open circle.
- Empty state that encourages creating the first circle.
- Create-circle flow should not silently create “New Memory Circle”; use a small form/dialog.
- Use “family circle” or “memory circle” language consistently.
- Keep creation to the minimum fields: name and optional short description.

### 5. Redesign Circle Dashboard

Make the dashboard useful and scannable:

- Show circle name and description.
- Provide quick actions: Add Memory, Review Pending, Generate/Open Album, Members.
- Show small status panels from available API data where reasonable:
  - approved memories count
  - pending memories count
  - album count
  - health status
- Keep it warm and operational, not flashy.
- Prefer a “What would you like to do?” style layout over a technical control panel.
- Show counts in plain language, such as “8 memories in the album” and “1 waiting for review”.

### 6. Redesign Add Memory

Improve the contribution flow:

- Image picker/upload should feel first-class.
- Show selected/uploaded image preview if possible.
- Caption, story, event name, date, location fields.
- Submit for approval.
- Clear upload/submission progress.
- Useful error handling.
- Use a step-by-step feel:
  1. Choose photo.
  2. Add the story.
  3. Send for review.
- Label fields in everyday language:
  - “Short caption”
  - “What is the story behind this photo?”
  - “When did this happen?”
  - “Where was this?”
- If upload fails, say something like “We could not upload this photo. Try a JPEG, PNG, or WebP image.”

If authenticated preview images are hard in Flutter web/desktop, implement a practical helper in the API client to fetch bytes with Authorization headers and display via `Image.memory`.

### 7. Redesign Approval Review

Approvers need a focused review experience:

- Pending memory list with thumbnails, caption, event/date, contributor if available.
- Detail/review view.
- Approve, reject, request changes.
- Allow edit-and-approve for caption/story/event/location if practical.
- Viewers/contributors should not see controls they cannot use, but remember server-side enforcement already exists.
- Phrase actions clearly:
  - “Add to album”
  - “Ask for changes”
  - “Do not include”
- Avoid words like “approve endpoint”, “pending queue”, or “approval_status” in UI.

### 8. Redesign Albums and Flip Album

This is the MVP differentiator. Treat it as the centerpiece.

Albums screen:

- Show albums as album covers/cards.
- Allow creating/generating an album from approved memories.
- Clear empty state when there are no albums.
- Use gentle language such as “Create album from approved memories”.

Flip album screen:

- Desktop: two-page spread when width permits.
- Mobile: single-page view.
- Tap/click right side advances.
- Tap/click left side goes back.
- Swipe left/right on touch devices.
- Keyboard: right arrow/space next, left arrow previous, escape exits fullscreen if implemented.
- Add fullscreen button on desktop/web where feasible.
- Render album layout JSON templates:
  - `event_title`
  - `one_photo_feature`
  - `two_photo_story`
  - `four_photo_grid`
- Always show captions.
- Show story preview where there is space.
- Use authenticated asset display URLs.
- Make pages feel like paper without making text hard to read.
- Controls should be discoverable but minimal: previous, next, fullscreen, close.
- If there are no pages, explain simply: “This album is empty until memories are added.”

### 9. Members, Health, Settings

Members:

- Show member name/email/role/status clearly.
- Provide owner-oriented role controls if simple and safe.
- Explain roles in plain language when editing:
  - Owner: manages the circle.
  - Reviewer: can add memories to the album.
  - Contributor: can send memories.
  - Viewer: can view the album.

Health:

- Call `/circles/{circle_id}/health`.
- Show cache/asset health in a friendly placeholder-style view.
- Keep future archive/device recovery clearly framed as future.
- Translate technical health into user language, for example “All display photos are ready” or “Some album photos need attention.”

Settings:

- Keep as a modest placeholder unless the current API supports circle patching cleanly.

### 10. Design System

Create reusable widgets and theme tokens:

- App colors.
- Text styles.
- Surface/card/button treatments.
- Spacing constants if useful.
- Reusable loading, empty, and error states.

Use Material icons. Prefer familiar icons over text-only controls for common actions.

## Backend API Contract

Use the existing API documented in:

```text
docs/API.md
```

Important endpoints:

```text
POST /auth/register
POST /auth/login
GET  /me

POST /circles
GET  /circles
GET  /circles/{circle_id}
PATCH /circles/{circle_id}

POST /circles/{circle_id}/invites
GET  /circles/{circle_id}/members
PATCH /circles/{circle_id}/members/{member_id}

POST /circles/{circle_id}/assets/upload
GET  /circles/{circle_id}/assets/{asset_id}/thumbnail
GET  /circles/{circle_id}/assets/{asset_id}/display

POST /circles/{circle_id}/memories
GET  /circles/{circle_id}/memories?status=approved|pending|rejected
GET  /circles/{circle_id}/memories/{memory_id}
PATCH /circles/{circle_id}/memories/{memory_id}
POST /circles/{circle_id}/memories/{memory_id}/submit
POST /circles/{circle_id}/memories/{memory_id}/approve
POST /circles/{circle_id}/memories/{memory_id}/reject
POST /circles/{circle_id}/memories/{memory_id}/request-changes

POST /circles/{circle_id}/albums
GET  /circles/{circle_id}/albums
GET  /circles/{circle_id}/albums/{album_id}
POST /circles/{circle_id}/albums/{album_id}/pages/generate
PATCH /circles/{circle_id}/albums/{album_id}/pages/{page_id}

GET /circles/{circle_id}/activity
GET /circles/{circle_id}/health
```

Default backend URL should remain configurable:

```dart
const apiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://127.0.0.1:8000',
);
```

## Implementation Expectations

Work directly in:

```text
apps/mobile_desktop_flutter/
```

Preserve the app’s ability to run with:

```bash
flutter pub get
flutter run -d chrome --dart-define=API_BASE=http://127.0.0.1:8000
```

Add or update tests where practical:

```bash
flutter test
```

Run formatting:

```bash
dart format lib test
```

If Flutter is not installed in the environment, still produce clean Flutter source and state that tests could not be run.

## Quality Bar

The redesign is complete when:

- The Flutter app is no longer a single-file prototype.
- Login/register flow is polished.
- Circle list and dashboard feel like a modern app.
- Add Memory supports image upload and story metadata cleanly.
- Pending approval has a real review flow.
- Albums are visually meaningful.
- Flip album is responsive, image-forward, and pleasant to use.
- Loading, error, and empty states are implemented.
- Authenticated image loading works for thumbnails/display images.
- The app remains compatible with the existing FastAPI backend.
- Documentation or README notes are updated if launch steps change.
- A non-technical user can understand each screen without knowing how the app is built.
- User-facing text uses plain, friendly language and avoids backend terminology.

## Important Constraints

- Do not remove working backend features.
- Do not change API endpoints unless absolutely necessary.
- Do not introduce a heavyweight state management framework unless the benefit is clear. Prefer simple, readable state for this MVP.
- Do not create a marketing landing page. The first screen after auth should be the usable app.
- Do not add fake AI, cloud connectors, payments, or social sharing.
- Keep the MVP focused on contribution, approval, album generation, and flip display.

## Final Report Requested

When finished, report:

1. Main files created/modified.
2. Visual/UX changes made.
3. How to run the redesigned app.
4. What tests or checks were run.
5. Any limitations or follow-up recommendations.
