# Codex Execution Plan for Memory Circle MVP

## Objective

Build a disciplined MVP for Memory Circle: a collaborative digital memory-album platform where users create Memory Circles, add photo-based memories, approve submissions, and display approved memories in a classic tap-to-flip album.

## Working method for Codex

Codex should operate in small verifiable increments. Each increment should produce code, tests where appropriate, and a short note on what changed.

## Phase 0: Repository assessment

If a repository already exists:

1. Inspect structure.
2. Identify language/framework.
3. Preserve existing conventions.
4. Create a migration plan instead of replacing everything.

If no repository exists:

1. Create monorepo.
2. Add backend, frontend, docs, scripts, infra folders.
3. Add baseline README.

Deliverable:

- Repository structure.
- Setup commands.
- Development assumptions.

## Phase 1: Backend foundation

Tasks:

1. Create backend application.
2. Configure environment variables.
3. Connect PostgreSQL.
4. Create database migrations.
5. Add health endpoint.
6. Add test framework.

Acceptance:

- API starts locally.
- Health endpoint works.
- Empty test suite runs.

## Phase 2: Authentication and authorization

Tasks:

1. Register endpoint.
2. Login endpoint.
3. Password hashing.
4. JWT/session handling.
5. Current user endpoint.
6. Role middleware for circle actions.

Acceptance:

- User can register/login.
- Protected endpoints reject unauthenticated requests.
- Role checks are enforced.

## Phase 3: Memory Circle model

Tasks:

1. Create MemoryCircle entity.
2. Create CircleMember entity.
3. Add owner role automatically.
4. Add invite/member management.
5. Add activity logging.

Acceptance:

- User can create circle.
- User can list own circles.
- Owner can add/update members.
- Viewer cannot manage members.

## Phase 4: Photo asset pipeline

Tasks:

1. Implement local upload endpoint.
2. Validate file type.
3. Store source reference.
4. Generate content hash.
5. Generate thumbnail.
6. Generate display-resolution copy.
7. Store asset metadata.

Acceptance:

- User can upload image.
- API returns asset id.
- Thumbnail and display copies are retrievable.
- Duplicate content hash is detected or recorded.

## Phase 5: Memory contribution workflow

Tasks:

1. Create MemoryItem entity.
2. Create draft/pending memory.
3. Add caption/story/event/date/location fields.
4. Submit for approval.
5. List memories by status.

Acceptance:

- Contributor can create memory.
- Submitted memory appears in pending queue.
- Viewer cannot create memory unless permitted.

## Phase 6: Approval workflow

Tasks:

1. Approve endpoint.
2. Edit-and-approve support.
3. Reject endpoint.
4. Request-changes endpoint.
5. ActivityLog for approval actions.

Acceptance:

- Approver can approve pending memory.
- Contributor cannot approve unless role allows.
- Approved memories become visible in album source list.

## Phase 7: Album and page generation

Tasks:

1. Create Album entity.
2. Create AlbumPage entity.
3. Implement simple page generator from approved memories.
4. Store page layout as JSON.
5. Return ordered pages for rendering.

Acceptance:

- Approved memories generate album pages.
- Pages include photo asset references, caption, and optional story.
- Album API returns layout_json.

## Phase 8: Flutter app foundation

Tasks:

1. Scaffold app.
2. Add routing.
3. Add auth state.
4. Add API client.
5. Add local cache/database placeholder.
6. Implement responsive layout skeleton.

Acceptance:

- App runs on desktop and mobile target.
- User can login/register.
- App can call backend.

## Phase 9: Core screens

Tasks:

1. My Memory Circles.
2. Create Circle.
3. Circle Dashboard.
4. Add Memory.
5. Pending Approval.
6. Memory Review.
7. Album List.
8. Members/Roles.

Acceptance:

- End-to-end contribution and approval can be completed through UI.

## Phase 10: Flip album display

Tasks:

1. Load album pages.
2. Render page layouts.
3. Implement next/previous.
4. Add desktop two-page spread.
5. Add mobile single-page view.
6. Add fullscreen mode.
7. Add keyboard controls.

Acceptance:

- User can view approved memories as flip album.
- Controls work on desktop and mobile.
- Display remains readable.

## Phase 11: Seed data and demo mode

Tasks:

1. Add demo users.
2. Add demo circle.
3. Add sample assets.
4. Add approved/pending/rejected memories.
5. Add generated album.

Acceptance:

- One command can seed demo data.
- Demo can be shown without manual setup.

## Phase 12: Testing and quality gate

Tasks:

1. Backend unit/API tests.
2. Frontend smoke tests.
3. Role authorization tests.
4. Upload tests.
5. Approval tests.
6. Album generation tests.
7. Setup instructions tested from clean clone.

Acceptance:

- All tests pass.
- README setup works.
- Known limitations documented.

## Phase 13: Documentation

Tasks:

1. Architecture documentation.
2. API documentation.
3. Data model documentation.
4. MVP scope documentation.
5. Security documentation.
6. Testing documentation.
7. Roadmap documentation.
8. Video storyboard documentation.

Acceptance:

- A new developer can understand and run the project.
- A product stakeholder can understand the MVP and roadmap.

## Backlog after MVP

1. Google Drive connector.
2. OneDrive connector.
3. iCloud import/export strategy.
4. Full local archive mode.
5. Peer/device recovery.
6. Archive health scoring.
7. Advanced album templates.
8. Shapes, clustering, frames, stickers.
9. Real-time collaborative layout editing.
10. Paid family/community plans.
