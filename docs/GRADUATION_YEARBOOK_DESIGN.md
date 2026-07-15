# Graduation Campaign and Digital Yearbook Design

Status: proposed pilot design  
Audience: product, design, backend, Flutter, QA, and university pilot organizers  
Scope: one university graduation, designed to generalize later

## 1. Recommendation

Build the pilot as one themed guest campaign linked to one generated yearbook album.
Use a constrained `ThemePreset` rather than a free-form page designer, and store
yearbook messages, profiles, dedications, and signatures as structured
contributions rather than photo captions.

The smallest coherent pilot includes:

- A graduation campaign preset and owner-facing campaign studio.
- University details, logo, approved colors, typography preset, cover, header,
  and footer choices.
- Campaign-specific photo, graduate profile, dedication, official message, and
  typed-signature submissions.
- Existing owner/approver moderation extended to all contribution types.
- A fixed set of reorderable yearbook sections.
- Deterministic themed digital album generation and preview.
- Revocable, expiring public sharing through a proper Flutter public viewer.
- Campaign-specific quotas and galleries.

Do not put PDF/photo-book export, arbitrary page positioning, custom fonts,
real-time co-editing, or uploaded handwritten signatures in the first pilot.
The data and layout contracts should support those later without requiring a
rewrite.

### Scope boundaries

| Boundary | Included |
|---|---|
| Existing capability | Circles and roles, guest photo links, verification, approval, assets, albums, JSON pages, flip display, and share-package APIs |
| Pilot MVP | One graduation preset, structured contributions, owner studio, campaign-scoped moderation/gallery, sections, themed revisions, and public Flutter viewer |
| Recommended follow-up | Handwritten signatures, constrained page editing, roster/SSO, PDF/print export, organization brand kits, and more event presets |
| Deliberately excluded | Free-form design canvas, custom code/fonts, real-time editing, facial recognition, print fulfillment, and multi-campus administration |

## 2. Existing Capability Audit

The code is ahead of parts of the older MVP documentation. The following is the
current baseline.

### Backend

- `backend/api/app/models.py` defines users, circles, role-bearing membership,
  photo assets, memories, albums, album pages, share packages, guest campaigns,
  and guest upload sessions.
- `backend/api/app/main.py` enforces circle roles server-side. Owners manage
  guest campaigns; owners and approvers manage albums and approval decisions.
- Guest campaigns currently store title, note, expiry, email-verification
  preference, token, creator, and revocation state.
- Guest uploads are attributed by guest name and email, enter the memory queue
  as pending, and are limited to 100 photos per guest email per campaign.
- The guest gallery is not currently campaign-scoped: `campaign_gallery()`
  selects all approved memories in the circle. The pilot must filter by
  `MemoryItem.campaign_id == campaign.id`.
- Memories support one photo plus caption, story, event, date, location, and
  people metadata. This is not sufficient for profiles, official messages,
  dedications, or signatures.
- Album generation supports title, description, cover memory, manual memory
  order, target photo count, and orientation-aware mosaic pages.
- Album `template_key` exists, but generation and Flutter rendering largely use
  one classic scrapbook treatment.
- Album page layout is stored as JSON. A page patch endpoint exists, but no
  complete visual editor uses it.
- Album size is capped at 12 photos per active circle member. This family rule
  is unsuitable for an institutional campaign.
- Share packages support saved, dated-expiry, and first-view access; optional
  captions and downloads; page selection; revocation; and protected public
  asset URLs.
- Upload validation decodes images with Pillow. Hosted assets can be stored as
  database blobs because the Render filesystem is ephemeral.

### Flutter

- `apps/mobile_desktop_flutter/lib/screens/campaigns_screen.dart` lets an owner
  create, share, extend, and close a guest link.
- `guest_campaign_screen.dart` supports no-account name/email registration,
  optional code verification, multi-image upload, and an approved gallery.
  It does not yet expose campaign branding or structured contribution forms.
- `albums_screen.dart` supports album creation, editing, cover choice, ordering,
  regeneration, sharing, and consensus-gated removal.
- `album_page_view.dart` renders a fixed scrapbook cover and orientation-aware
  content pages. The visual treatment does not consume a reusable theme.
- `flip_album_screen.dart` provides mobile single-page and wide two-page views,
  swipe/tap/keyboard navigation, and fullscreen mode.
- The app shell is responsive and exposes campaigns only to circle owners.
- A polished public share route/viewer is still needed; the backend public
  endpoint currently returns share data and protected public asset URLs.

### Deployment and constraints

- Flutter web is intended for GitHub Pages and the FastAPI API for Render.
- Hosted PostgreSQL stores display copies and thumbnails as blobs. The free
  database target is small, so pilot image budgets and compression matter.
- The repository does not yet use Alembic. Current schema helpers add columns
  and create tables at startup. New pilot tables need an explicit migration
  approach that works for both SQLite and PostgreSQL.
- Existing albums and their classic renderer must remain valid.

## 3. Product Model

The five product concepts have separate responsibilities:

| Concept | Responsibility | Lifetime |
|---|---|---|
| Memory Circle | Community, membership, roles, private assets, activity | Long-lived |
| Campaign | Collection window, guest identity, forms, consent, moderation context | Event-bound |
| Theme preset | Versioned visual rules and references to owned brand assets | Reusable |
| Album/yearbook | Curated publication, sections, page order, generated layout snapshot | Publishable artifact |
| Share package | Audience access, expiry, downloads, visible pages | Distribution-bound |

### Theme ownership and inheritance

Introduce a reusable, circle-owned `ThemePreset` referenced by both campaign
and album.

1. A preset contains constrained visual tokens and brand asset references.
2. A campaign selects a preset and may store allowed campaign-level overrides.
3. A linked album initially inherits the campaign's effective theme.
4. Each album generation stores `theme_snapshot_json` and
   `theme_snapshot_version`. Generated pages reference that snapshot.
5. Editing a preset does not silently alter a published album.
6. The owner sees "Theme updates available" and explicitly chooses to apply
   them. Applying creates a new album revision and regenerates generated pages.
7. Public share packages resolve the album revision they were created from,
   so an existing shared yearbook does not change unexpectedly.

This provides reuse without making published output mutable.

## 4. Pilot Domain Model

Use normalized records for identity, permissions, filtering, and moderation;
use validated JSON for preset-specific fields and layout instructions.

### `theme_presets`

| Field | Type | Notes |
|---|---|---|
| id | integer | Primary key |
| circle_id | foreign key | Asset and authorization boundary |
| name | varchar(160) | Example: "Engineering Graduation 2026" |
| preset_kind | varchar(60) | `university_graduation` for pilot |
| version | integer | Increment on each saved theme revision |
| tokens_json | text/json | Validated constrained theme tokens |
| created_by | foreign key | Owner |
| created_at, updated_at | datetime | Audit fields |
| archived_at | nullable datetime | Soft retirement |

### `brand_assets`

| Field | Type | Notes |
|---|---|---|
| id | integer | Primary key |
| circle_id | foreign key | Authorization boundary |
| theme_preset_id | nullable foreign key | Owning preset |
| kind | varchar(40) | `logo`, `secondary_mark`, `background`, `cover` |
| mime_type | varchar(80) | Pilot: PNG, JPEG, WebP |
| width, height, file_size | integer | Validation and rendering |
| content_hash | varchar(128) | Deduplication |
| display_blob/path | blob/path | Same storage strategy as photo assets |
| created_by | foreign key | Owner |
| rights_confirmed_at | datetime | Organizer attestation |
| created_at | datetime | Audit |

SVG should be excluded from the pilot because sanitizing active SVG content is
easy to get wrong. Transparent PNG is the recommended logo format.

### Changes to `guest_campaigns`

Add:

- `campaign_type`, default `photo_collection` for existing campaigns.
- `theme_preset_id`, nullable.
- `details_json`, validated graduation metadata.
- `contribution_settings_json`, enabled types and field requirements.
- `consent_text`, snapshotted when the campaign is published.
- `status`: `draft`, `published`, `closed`, `archived`.
- `published_at`, nullable.
- `linked_album_id`, nullable.
- `participant_quota`, default 250 for the pilot.
- `total_contribution_quota`, default 1500 for the pilot.
- `per_guest_photo_quota`, default 20 for the pilot.

Existing campaigns migrate to `photo_collection` and preserve current open or
revoked behavior.

### `campaign_contributors`

This replaces repeated guest sessions as the durable campaign identity while
allowing the existing token flow to remain during migration.

- `id`, `campaign_id`, `guest_name`, normalized `guest_email`.
- `verification_status`, `verified_at`, and last session timestamp.
- Optional `student_identifier` stored encrypted or hashed when the university
  requires roster matching. Do not collect it by default.
- `consent_version`, `consented_at`, `withdrawn_at`.
- Unique constraint on `(campaign_id, normalized_email)`.

### `campaign_contributions`

| Field | Purpose |
|---|---|
| id, campaign_id, contributor_id | Ownership and campaign scoping |
| contribution_type | `photo_memory`, `graduate_profile`, `dedication`, `official_message`, `typed_signature`, `acknowledgement` |
| payload_json | Type-specific validated fields |
| asset_id | Optional photo asset |
| signature_asset_id | Reserved for a later handwritten-signature phase |
| moderation_status | `draft`, `pending`, `changes_requested`, `approved`, `rejected`, `withdrawn` |
| votes_json | Existing consensus-review semantics |
| visibility | Pilot: `yearbook`, `organizers_only`; future: section or recipient scopes |
| display_name | Snapshotted attribution name |
| consent_version, consented_at | Evidence for publication |
| sort_hint | Owner-controlled ordering within a section |
| created_at, updated_at | Audit |

Suggested payloads:

```json
{
  "type": "graduate_profile",
  "full_name": "Amina Kamau",
  "preferred_name": "Amina",
  "programme": "BSc Computer Science",
  "honours": "First Class Honours",
  "quote": "Build with care.",
  "future_plans": "Graduate software engineer",
  "photo_asset_id": 812
}
```

```json
{
  "type": "dedication",
  "message": "To everyone who carried us through the difficult weeks...",
  "from_name": "Class of 2026",
  "recipient_label": "Our families and lecturers"
}
```

Typed signatures should store the contributor's entered display name plus a
selected presentation style. Do not generate a handwriting facsimile from a
typed name in the pilot; use clearly typographic signature treatments.

### `yearbook_sections`

- `id`, `album_id`, `section_type`, `title`, `subtitle`.
- `position`, `enabled`, `layout_variant`.
- `settings_json` for constrained section options.
- `source_rule_json` describing included contribution types or explicit IDs.
- `manual_content_json` for owner-authored static text.
- `created_at`, `updated_at`.

### Changes to `albums`

Add:

- `album_kind`, default `classic`; pilot uses `graduation_yearbook`.
- `campaign_id`, nullable.
- `theme_preset_id`, nullable.
- `theme_snapshot_json`, nullable.
- `theme_snapshot_version`, nullable.
- `revision`, default 1.
- `publication_status`: `draft`, `published`, `superseded`.
- `published_at`, nullable.
- `quota_policy`: `circle_members` or `campaign`.

Existing albums default to `classic` and retain the 12-per-member rule.
Graduation albums use the linked campaign quota and approved structured
contributions instead.

## 5. Constrained Theme Contract

Example `tokens_json`:

```json
{
  "schema_version": 1,
  "colors": {
    "primary": "#123A63",
    "secondary": "#E8EEF3",
    "accent": "#C9A227",
    "text": "#17202A",
    "background": "#FFFFFF"
  },
  "assets": {
    "logo_id": 31,
    "secondary_mark_id": null,
    "cover_asset_id": 44,
    "background_asset_id": null
  },
  "typography": {
    "preset": "formal_serif",
    "heading_scale": "standard",
    "body_scale": "standard"
  },
  "cover": {
    "layout": "crest_centered",
    "overlay": "none",
    "show_date": true
  },
  "header": {
    "variant": "logo_and_section",
    "alignment": "center",
    "text": "Faculty of Engineering"
  },
  "footer": {
    "variant": "event_and_page",
    "text": "Graduation 2026",
    "show_page_number": true,
    "show_logo": false
  },
  "page": {
    "format": "screen_portrait_3_4",
    "background": "solid",
    "photo_frame": "formal_white",
    "signature_style": "clean_script",
    "screen_safe_margin": 32,
    "print_safe_margin_mm": 12,
    "bleed_mm": 3
  }
}
```

Validation rules:

- Colors are six-digit hex values and must pass WCAG AA for body text. Show a
  blocking validation error with an automatically suggested accessible color.
- Typography is selected from bundled, licensed presets only.
- Logo: PNG/WebP, maximum 4 MB, 400-3000 px on its longest edge; transparent
  PNG recommended.
- Background/cover: JPEG/PNG/WebP, maximum 10 MB, minimum 1600 px long edge.
- Decode every image server-side, strip metadata, normalize orientation, create
  thumbnails/display copies, and reject decompression bombs.
- Every asset must belong to the same circle as the preset and campaign.
- Store the rights attestation and show it before first publication.
- No arbitrary CSS, HTML, JavaScript, remote image URLs, or uploaded fonts.

## 6. Owner Experience: Campaign Studio

Use a wide-screen stepper or tabs and a linear mobile flow. Autosave completed
fields after a short debounce, show explicit `Saving`, `Saved`, and `Failed`
states, and block navigation only when a file upload or invalid edit cannot be
persisted.

### Details

- University, faculty, department, cohort, graduation date, venue, motto.
- Campaign title, organizer message, closing date, and contact details.
- Draft/published status and a preview-link action.

### Branding

- Start from "University Graduation".
- Logo and cover upload with crop/contain preview.
- Color swatches, bundled typography presets, cover/header/footer choices.
- Mobile and desktop previews using the real renderer.
- Reset individual token or entire preset to defaults.

### Contributions

- Toggle allowed contribution types.
- Choose required profile fields and character limits.
- Set participant and per-person quotas.
- Edit consent and attribution text before publication.
- Once contributions exist, destructive form changes require confirmation and
  show how many submissions would become incomplete.

### Yearbook Structure

- Start from the graduation section list.
- Reorder sections with accessible move-up/move-down controls and desktop drag
  handles.
- Enable or disable optional sections.
- Select one of a small number of layout variants per section.
- Show source counts, for example "86 approved graduate profiles".

### Moderation

- Filters by contribution type, status, contributor, and missing consent.
- Preview the final themed treatment while reviewing.
- Approve, reject, request changes, and edit permitted text fields.
- Preserve the existing consensus rule for owners and approvers.
- Bulk approval is excluded from the pilot; bulk rejection should also be
  avoided because of its blast radius.

### Preview

- Campaign landing preview and yearbook preview.
- Mobile, desktop single-page, and desktop spread modes.
- Warnings for missing logo, low-resolution assets, low contrast, empty required
  sections, overflow, and unpublished changes.
- Regeneration must create a draft revision; the current published revision
  remains shareable until the owner publishes the replacement.

### Publish

- Preflight checklist: rights confirmed, consent version frozen, no required
  sections empty, contrast valid, assets available, and moderation queue clear
  or explicitly accepted.
- Publish campaign independently from publish yearbook.
- Create/copy QR and guest link after campaign publication.
- Create a share package after yearbook publication.
- Applying theme changes to a published yearbook requires an explicit new
  revision and confirmation.

### Flutter screen hierarchy

```text
CircleShell
`-- CampaignsView
    |-- CampaignPresetPicker
    `-- CampaignStudioScreen
        |-- DetailsStep
        |-- BrandingStep
        |-- ContributionSettingsStep
        |-- YearbookStructureStep
        |-- CampaignModerationStep
        |-- CampaignPreviewStep
        `-- PublishStep

GuestCampaignScreen
|-- CampaignLandingView
|-- GuestIdentityView
|-- ConsentView
|-- ContributionTypePicker
|-- StructuredContributionForm
|-- ContributionPreview
`-- ContributorSubmissionsView

AlbumRevisionPreviewScreen
`-- ThemedAlbumPageView

PublicYearbookScreen
`-- ThemedAlbumPageView
```

`ThemedAlbumPageView` should become the shared semantic renderer. The classic
album continues through its current schema-version-1 branch.

## 7. Guest Experience

The first viewport should identify the institution and event through the logo,
university/faculty name, campaign title, graduation date, and approved colors.
It should not look like the generic family scrapbook.

Flow:

1. Open link or QR code.
2. See campaign identity, organizer message, closing date, and privacy summary.
3. Enter name and email; verify when configured.
4. Accept the versioned publication consent.
5. Choose a contribution type.
6. Complete a short mobile form, preview it, and submit.
7. See pending status and edit/withdraw options while the campaign remains open.
8. View only approved contributions from this campaign when the organizer has
   enabled the gallery.

Persist a verified contributor session locally for the campaign so multiple
contributions do not require repeated verification. Do not expose contributor
emails, internal moderation status, organizer-only contributions, or assets
from another campaign.

## 8. API Proposal

Representative owner endpoints:

```text
POST   /circles/{circle_id}/theme-presets
GET    /circles/{circle_id}/theme-presets
GET    /circles/{circle_id}/theme-presets/{preset_id}
PATCH  /circles/{circle_id}/theme-presets/{preset_id}
POST   /circles/{circle_id}/theme-presets/{preset_id}/assets
DELETE /circles/{circle_id}/theme-presets/{preset_id}/assets/{asset_id}

POST   /circles/{circle_id}/campaigns/from-preset
GET    /circles/{circle_id}/campaigns/{campaign_id}/studio
PATCH  /circles/{circle_id}/campaigns/{campaign_id}/details
PATCH  /circles/{circle_id}/campaigns/{campaign_id}/contribution-settings
POST   /circles/{circle_id}/campaigns/{campaign_id}/publish
GET    /circles/{circle_id}/campaigns/{campaign_id}/contributions
POST   /circles/{circle_id}/campaigns/{campaign_id}/contributions/{id}/approve
POST   /circles/{circle_id}/campaigns/{campaign_id}/contributions/{id}/reject
POST   /circles/{circle_id}/campaigns/{campaign_id}/contributions/{id}/request-changes

POST   /circles/{circle_id}/campaigns/{campaign_id}/yearbook
GET    /circles/{circle_id}/albums/{album_id}/sections
PATCH  /circles/{circle_id}/albums/{album_id}/sections/{section_id}
POST   /circles/{circle_id}/albums/{album_id}/revisions/generate
POST   /circles/{circle_id}/albums/{album_id}/revisions/{revision}/publish
```

Representative guest endpoints:

```text
GET    /campaigns/{token}
POST   /campaigns/{token}/contributors
POST   /campaigns/{token}/contributors/verify
GET    /campaigns/{token}/contribution-schema
POST   /campaigns/{token}/contributions
PATCH  /campaigns/{token}/contributions/{id}
POST   /campaigns/{token}/contributions/{id}/submit
POST   /campaigns/{token}/contributions/{id}/withdraw
GET    /campaigns/{token}/gallery
GET    /campaigns/{token}/assets/{asset_id}/{variant}
```

All guest contribution mutation endpoints require a campaign-scoped
contributor token. Asset routes must verify that the asset is referenced by the
requested campaign and is allowed in the current context.

Example campaign creation:

```json
POST /circles/42/campaigns/from-preset
{
  "preset": "university_graduation",
  "title": "Faculty of Engineering Graduation 2026",
  "details": {
    "university": "Example University",
    "faculty": "Faculty of Engineering",
    "cohort": "Class of 2026",
    "graduation_date": "2026-12-18",
    "venue": "Great Hall"
  },
  "expires_at": "2026-12-31T23:59:59Z"
}
```

Example response:

```json
{
  "id": 73,
  "circle_id": 42,
  "campaign_type": "university_graduation",
  "status": "draft",
  "title": "Faculty of Engineering Graduation 2026",
  "theme_preset_id": 18,
  "linked_album_id": null,
  "quota": {
    "participants_used": 0,
    "participants_limit": 250,
    "contributions_used": 0,
    "contributions_limit": 1500
  },
  "validation": {
    "can_publish": false,
    "errors": ["theme.logo_required", "consent.required"]
  }
}
```

Error responses should identify fields with stable codes such as
`theme.low_contrast`, `asset.wrong_circle`, `campaign.quota_reached`,
`consent.required`, and `contribution.schema_changed`.

## 9. Layout and Rendering

Keep page layouts semantic. Do not store pixel coordinates as the primary
contract.

```json
{
  "schema_version": 2,
  "template": "graduate_profile_pair",
  "page_number": 12,
  "section_id": 7,
  "theme_snapshot_version": 3,
  "slots": [
    {"kind": "graduate_profile", "contribution_id": 91},
    {"kind": "graduate_profile", "contribution_id": 104}
  ],
  "header": {"section_title": "Class of 2026"},
  "footer": {"show_page_number": true}
}
```

The renderer maps semantic templates and tokens to constrained Flutter
widgets. Use the same renderer for authenticated albums, campaign previews,
public shares, and future export. Each template must define:

- Supported slot types and maximum text lengths.
- Deterministic overflow behavior.
- Mobile and spread-safe composition.
- Screen and print safe areas.
- Accessibility semantics and reading order.

Generation rules:

- Separate generated pages from owner-authored manual content.
- Regeneration may replace generated pages in a draft revision only.
- Approved contributions remain source records and are never deleted by page
  regeneration.
- Manual section text is stored on the section, not embedded only in a page.
- A removed or withdrawn contribution marks affected draft pages stale and
  triggers regeneration; published revisions remain auditable and can be
  withdrawn from active shares when legally required.
- Existing schema-version-1 pages continue through the classic renderer.

Pilot templates:

- `graduation_cover`
- `official_message`
- `graduate_profile_single`
- `graduate_profile_pair`
- `photo_mosaic`
- `dedication_grid`
- `typed_signature_grid`
- `acknowledgements`
- `graduation_back_cover`

## 10. Permissions

| Action | Owner | Approver | Contributor/member | Guest | Viewer/public |
|---|---:|---:|---:|---:|---:|
| Manage campaign/theme | Yes | No | No | No | No |
| Upload brand assets | Yes | No | No | No | No |
| Configure sections | Yes | Optional later | No | No | No |
| Review contributions | Yes | Yes | No | No | No |
| Submit contribution | Yes | Yes | Yes | Own campaign | No |
| Edit/withdraw own pending contribution | Yes | Yes | Yes | Own only | No |
| Generate yearbook draft | Yes | Yes | No | No | No |
| Publish yearbook/share | Yes | No | No | No | No |
| View approved album | Yes | Yes | Yes | If allowed | Share scope only |

Owner edits to a contributor's approved text must be activity-logged. Material
edits should return the contribution to pending unless the pilot organizer has
an explicit editorial-consent clause.

## 11. Quotas and Storage

Do not reuse the 12-photos-per-active-member rule for graduation albums.

Pilot defaults:

- Up to 250 verified contributors.
- Up to 20 photos per contributor.
- Up to 1 graduate profile per verified email.
- Up to 5 text contributions per contributor.
- Up to 1,500 approved contributions in the campaign.
- Up to 400 selected items in the first published yearbook revision.

These are policy defaults, not hard-coded product constants. Store them on the
campaign and return quota use in owner and guest responses. Use compressed
display assets and monitor database use because the current hosted database
also stores image blobs.

## 12. Privacy, Security, and Removal

- Freeze and version consent text at campaign publication.
- Record consent version and timestamp on every contribution.
- Clearly identify intended audience and whether downloads are allowed.
- Let a contributor withdraw pending content while the campaign is open.
- Provide an organizer removal workflow after publication. Revoke or regenerate
  active share packages when a lawful removal affects published pages.
- Treat typed signatures and personal messages as personal data, not decoration.
- Never expose guest email in gallery, album layout, or public-share responses.
- Keep branding assets private unless an active campaign/share route authorizes
  them.
- Rate-limit contributor registration, verification, upload, and submission.
- Add resend limits, verification attempt limits, and token expiration.
- Strip EXIF metadata from public display copies unless the owner deliberately
  enables safe capture dates.
- Validate every nested JSON payload with typed Pydantic models.
- Log theme changes, publication, moderation, consent withdrawal, and removals.
- Back up the pilot database before publication and before destructive schema
  migration.

## 13. Testing

### Backend

- Only owners create or alter presets, branding, campaign settings, and publish.
- Approvers can moderate but cannot publish or replace brand assets.
- Assets cannot cross circle, campaign, album, or share-package boundaries.
- Campaign gallery returns only approved contributions for that campaign.
- Every contribution type validates required fields and limits.
- Consent is required and versioned; withdrawn content cannot regenerate.
- Consensus approval works for non-photo contributions.
- Campaign quotas are enforced without using active-member count.
- Theme snapshots remain stable after the source preset changes.
- Regeneration preserves source contributions and manual section content.
- Existing classic albums and share packages still serialize and render.
- Expired/revoked campaigns and shares deny metadata and assets correctly.
- Image validation rejects wrong MIME types, corrupt files, oversized images,
  unsafe dimensions, and assets owned by another circle.

### Flutter

- Studio steps save, recover from failure, and warn on unsaved uploads.
- Long institution names and messages do not overflow at mobile widths.
- Theme contrast errors are visible and block publication.
- Guest contribution forms are generated correctly for each enabled type.
- Contributor session restoration never crosses campaign tokens.
- Moderation filters and themed previews match contribution status.
- Classic album golden tests remain unchanged.
- Every pilot template has golden tests at phone, tablet, and desktop spread
  sizes, including maximum-length text and missing optional assets.
- Public viewer handles active, expired, revoked, and superseded shares.

### Manual pilot script

1. Create the graduation campaign and upload a logo.
2. Configure forms, sections, quotas, and consent; preview phone and desktop.
3. Publish and open the QR link on at least one iOS and one Android browser.
4. Submit each contribution type from two guest identities.
5. Approve, request changes, reject, edit, and withdraw representative items.
6. Generate a draft, change the preset, and verify the draft/published boundary.
7. Publish and open the shared yearbook on phone and desktop.
8. Revoke the share and verify all public assets stop resolving.
9. Confirm an existing classic family album still works.

## 14. Migration and Backward Compatibility

Introduce Alembic before or as part of the pilot's first schema change. Generate
and review migrations against both SQLite development databases and hosted
PostgreSQL. Do not rely on startup-time `ALTER TABLE` helpers for the larger
relational change.

Migration sequence:

1. Add new nullable album and campaign columns with compatibility defaults.
2. Create theme, brand asset, contributor, contribution, and section tables.
3. Backfill existing campaigns as `photo_collection` and existing albums as
   `classic` with `quota_policy = circle_members`.
4. Keep existing `MemoryItem.campaign_id` records and expose them as legacy
   photo contributions through an adapter; do not duplicate image blobs.
5. Route page JSON without `schema_version` to schema version 1.
6. Deploy read compatibility before enabling any writes using the new schema.
7. Enable the graduation preset behind a server-controlled feature flag for the
   pilot circle.
8. Back up PostgreSQL and rehearse rollback before enabling guest traffic.

Old clients must continue receiving the current campaign and album fields.
Additive response fields are acceptable; do not change current field meanings.
A new client encountering an old campaign opens the existing guest photo flow.
An old client encountering a graduation campaign should receive an explicit
"Update required for this campaign" response rather than a malformed photo-only
experience.

### Edge cases

- Campaign expires while a guest is uploading: finish an already accepted
  upload transaction, but reject new submissions and preserve the draft.
- Theme or logo changes while preview is open: mark preview stale and require a
  refresh before publication.
- Contributor submits twice with differently cased email: normalize and reuse
  the contributor identity.
- Two graduate profiles claim the same email: allow only one active profile and
  expose edit/withdraw rather than creating a duplicate.
- Approved contribution loses consent: exclude it from new revisions, flag
  active shares, and start the removal workflow.
- Approver count changes mid-review: reuse the current active-reviewer
  calculation and clearly show the updated threshold.
- Brand asset is deleted while referenced: block deletion until replacement or
  remove it only from drafts; published snapshots retain an authorized copy.
- A page has too much text: block publication with a field-specific preflight
  error; never silently truncate official messages or names.
- Share package points to a superseded revision: continue serving that immutable
  revision until revoked or expired.
- Database quota is approached: disable new image uploads before text
  submissions, notify the owner, and preserve existing content.
- Guest gallery is disabled: return no gallery metadata or public asset routes,
  not merely a hidden Flutter widget.
- Campaign closes with pending submissions: let organizers finish moderation,
  but prevent contributors from creating new submissions.

## 15. Analytics for the Pilot

Collect product events without logging contribution text or guest email:

- Campaign created, configured, previewed, and published.
- Guest link opened, registration started/completed, verification completed.
- Contribution form started, submitted, abandoned, or failed by type.
- Moderation turnaround and outcome by type.
- Yearbook draft generated, preflight warnings, and publication success.
- Public share opened, page depth, device class, and asset failures.
- Quota and storage utilization.
- Withdrawal/removal requests.

Pilot success targets should be agreed with the university. Suggested initial
targets are 70% of invited graduates verified, 60% submitting a profile, 90%
of started submissions completing, median moderation under 48 hours, no
cross-campaign privacy incidents, and less than 1% public asset-load failure.

## 16. Phased Delivery

### Phase 0: Decisions and sample content

- Confirm institution, cohort size, permitted branding, organizer roles,
  consent text, intended audience, and whether the university requires PDF.
- Obtain representative long names, messages, logos, portrait/landscape photos,
  and section counts for layout testing.

Acceptance: signed pilot brief, brand permission, privacy owner, and sample-data
pack exist.

### Phase 1: Data foundation and campaign correctness

- Add migrations, theme/brand/contribution/section models, campaign status and
  quotas, typed schemas, asset authorization, and campaign-scoped gallery fix.
- Preserve existing campaign and album contracts.

Acceptance: backend tests pass on SQLite and PostgreSQL; cross-scope asset tests
and migration rollback rehearsal pass.

### Phase 2: Campaign studio and guest contribution

- Build owner Details, Branding, Contributions, and Publish steps.
- Build themed guest landing, consent, contributor session, and structured
  forms.

Acceptance: organizer creates and publishes a valid campaign without developer
help; a guest completes each enabled type on a phone.

### Phase 3: Moderation and yearbook generation

- Extend moderation to structured contributions.
- Add sections, theme snapshotting, deterministic templates, revisions, and
  preflight preview.

Acceptance: approved pilot content generates without overflow; regeneration
preserves manual and source content; classic albums remain unchanged.

### Phase 4: Public viewer and pilot hardening

- Add Flutter public-share route, asset failure handling, accessibility review,
  analytics, rate limits, backup procedure, and device/browser QA.

Acceptance: active, expired, and revoked shares behave correctly across target
devices; launch checklist is signed off.

### Follow-up after pilot

- Uploaded handwritten signatures with cropping and stricter consent.
- PDF and print-ready export using the same semantic renderer contract.
- Recipient-scoped dedications and private messages.
- Roster import and university SSO.
- More event presets, organization-level brand kits, and reusable sections.
- Explicit page-level editing within constrained templates.

## 17. Deliberately Excluded from the Pilot

- General-purpose drag-and-drop canvas.
- Arbitrary CSS, HTML, uploaded fonts, and executable SVG.
- Real-time collaborative editing.
- AI-written profiles, comments, or signatures.
- Facial recognition and automatic people identification.
- Native print ordering or fulfillment.
- University-wide multi-department administration.
- Roster import, SSO, and payment/subscription changes.
- Full-resolution original-photo archive guarantees.

## 18. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Scope expands into a design suite | Fixed preset, tokens, sections, and templates |
| Published output changes unexpectedly | Immutable theme snapshots and album revisions |
| Unrelated photos leak into a campaign | Filter by campaign ID and test every asset route |
| Personal messages/signatures are misused | Versioned consent, moderation, withdrawal, audit |
| Long names or messages break layouts | Character limits, preflight, golden tests, deterministic overflow |
| University logo use is unauthorized | Rights attestation and named institutional approver |
| Free-tier database fills with images | Configurable quotas, compression, usage dashboard, backups |
| Family albums regress | Schema-version routing and classic golden tests |
| Owner regenerates away manual work | Source records, section content, and revision-based generation |
| Public share JSON has no polished viewer | Dedicated Flutter public route before pilot launch |

## 19. Founder Decisions Required

1. Is the pilot's final artifact digital-only, or is a PDF contract required at
   launch even if PDF export follows later?
2. Who legally controls consent and removal requests: the circle owner, the
   university, or both?
3. Are graduate profiles visible to every campaign guest during collection, or
   only after yearbook publication?
4. Is consensus approval required for every contribution, or may the university
   appoint a smaller editorial board?
5. May organizers materially edit graduate text, or must edited text return to
   the graduate for confirmation?
6. What cohort size, expected photo count, retention period, and database budget
   define the real quotas?
7. Should one email represent one graduate, and is roster matching required?
8. Are sponsors permitted, and who approves secondary marks?
9. Should public shares permit downloads by default? The recommendation is no.
10. How long should guest identity, raw submissions, rejected content, and
    public analytics be retained?

## 20. Why This Is the Right Pilot Scope

This scope proves the new value proposition without replacing Memory Circle's
working core. It reuses guest access, role enforcement, moderation, assets,
album pages, flip display, and share-package security. It adds only the missing
institutional layer: a brand preset, structured contributions, sections,
revision-safe generation, and a themed public experience.

The result is meaningfully more than a branded upload page: it completes the
loop from invitation to moderated contribution to recognizable graduation
yearbook. At the same time, constrained presets and semantic templates keep the
pilot buildable, testable, accessible, and reusable for the next event type.
