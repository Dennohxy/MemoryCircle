# Data Model

The MVP implements these tables:

- `users`
- `memory_circles`
- `circle_members`
- `photo_sources`
- `photo_assets`
- `memory_items`
- `albums`
- `album_pages`
- `activity_logs`

Important boundaries:

- `PhotoSource` records where the image came from.
- `PhotoAsset` records generated cache files and technical image metadata.
- `MemoryItem` records the human story and approval state.
- `AlbumPage` stores layout JSON for the flip display.
