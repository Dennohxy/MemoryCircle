# Album Photo Count Plan

## Approved Decision (founder, 2026-07-08)

The album size scales with the family, instead of a fixed default:

- **Maximum album size = 12 photos x number of active circle members.**
- Members are never limited in how many photos they can *propose* (upload).
- Reviewers may set a smaller per-album target; anything above the family
  maximum is rejected with a clear message.
- When no target is set, page generation uses the family maximum.
- If members leave after a target was set, the cap still holds at generation
  time (`min(target, 12 x members)`).

The API exposes both values on every album: `target_photo_count` (effective)
and `max_photo_count` (the 12-per-member ceiling).

## Page Layout Rule

Until face detection/cropping tools are available, generated pages should prefer:

- One featured photo when a story is important.
- Two-photo pages for related memories.
- No automatic four-photo collage when faces may be cropped.

The app should render photos with `contain` fitting by default, so the whole
photo remains visible. Empty margins are acceptable if that protects faces.

## Member Agreement Flow

Before page generation:

1. Members upload all candidate photos (no upload limit).
2. Every reviewer (owner + approvers) approves each photo that may enter the
   album. Founder decision 2026-07-08: viewers and contributors do not vote,
   so a passive member cannot stall an album.
3. A reviewer optionally sets a planned photo count within the family maximum.
4. A reviewer chooses the cover photo and sequence.
5. Pages are generated from approved photos only.
