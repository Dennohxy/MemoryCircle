# Album Photo Count Plan

This plan is for approval before Memory Circle treats any album size as the
product default.

## Recommendation

Use a default album target of **24 photos**.

Why:

- It is large enough to feel complete for a family event.
- It stays short enough for a comfortable flip-through session.
- It creates predictable page generation without forcing dense collages.
- It supports face-safe layouts with one or two photos per page.

## Proposed Presets

```text
Small keepsake      12 photos
Standard album      24 photos
Big family event    36 photos
Archive edition     60 photos
```

## Page Layout Rule

Until face detection/cropping tools are available, generated pages should prefer:

- One featured photo when a story is important.
- Two-photo pages for related memories.
- No automatic four-photo collage when faces may be cropped.

The app should render photos with `contain` fitting by default, so the whole
photo remains visible. Empty margins are acceptable if that protects faces.

## Member Agreement Flow

Before page generation:

1. Members upload all candidate photos.
2. Every active circle member approves each photo that may enter the album.
3. A reviewer sets the planned photo count.
4. A reviewer chooses the cover photo and sequence.
5. Pages are generated from approved photos only.

## Open Decision

Approve one default:

```text
[ ] 12 photos
[ ] 24 photos
[ ] 36 photos
[ ] Custom default: ______
```
