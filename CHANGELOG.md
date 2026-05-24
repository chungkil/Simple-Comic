# Changelog

All notable changes to Simple Comic. Format roughly follows [Keep a Changelog](https://keepachangelog.com/).

## [1.8.0] - 2026-05-24

### Added
- **Webtoon mode (⌘J)** — continuous vertical-scroll reading for long-strip / Korean webtoon archives, with centered layout on the widest page (`8b11454`, `f9be373`)
- Webtoon mode keyboard scrolling and loupe support (`b9dabc3`)
- Webtoon mode live-preview of pending page rotations (`42210db`)
- Webtoon page gap and max-width settings (`a0c074f`)
- **Library window (⌘Y)** with cover thumbnails (`9e89194`, `a9ee11d`)
- Library: scan designated folder for works (`19138bc`)
- Library: dim works whose source file is missing (`e73c0a6`)
- Library: search, sort, cover-size slider, unread badge (`e1a7e03`)
- Library: multiple folders + recursive scan (image folder = leaf work) (`2ea03ef`)
- Library: continue-reading shelf for recent works (`efda4a1`)
- **Per-work reading progress** and named bookmarks (last page + scroll position + layout mode persisted) (`f1fa0f1`)
- Bookmarks: per-item rename and delete (`f980168`)
- Bookmarks: thumbnail preview on menu items (`ac1bbcc`)
- **Page editing** persisted to source on close:
  - Remove Page defers to close, repacks CBZ, drops AppleDouble ghosts (`b58cd3c`)
  - Rotate pages and save back to the archive/folder (`fa0841d`)
  - Drag-to-reorder pages in thumbnail expose; save on close (`5e9adbe`)
  - Convert CBR/7z archives to CBZ for editing (`8dbe9ff`)
  - Bulk rotate all pages + ⌘[/⌘] move up/down shortcuts (`b22f944`)
  - Option to preserve subdirectory layout when reordering (`2128858`)
- Paged image prefetch — page turns no longer block on decode (`2b82ac3`)
- Reading statistics window (`a3a5025`)
- App version driven by git tag via xcconfig (`252d808`)
- **Thumbnail Exposé rewrite (T)** on NSCollectionView — HUD blur backdrop, hover preview up to 720pt, click-to-jump, Esc to dismiss, drag-to-reorder (`596f9b6`)
- Redacted Safari extension (separate target, unrelated to main app) (`f2becd7`)

### Changed
- Default loupe diameter bumped 500 → 1200pt (`6351982`)
- Loupe diameter max clamp raised 500 → 1500pt (`71380c4`)
- Loupe diameter persisted across launches — ⌘+scroll writes to defaults, restored on next session (`d9be3b4`)
- `workIdentifier` returns nil for multi-source sessions so progress is not silently keyed on the first archive only (`f3791f9`)

### Fixed
- Thumbnail Exposé black-screen on modern macOS — NSImage `lockFocus` on background thread + Core Data writes off-main caused empty thumbnails. Switched `prepThumbnail` to NSBitmapImageRep-backed offscreen drawing and dispatched the `thumbnailData` cache write back to the main queue (`30dbe3d`). Superseded by the full rewrite (`596f9b6`).
- Loupe: stop forcing 1000pt on session restore (was overriding the saved diameter) (`d9be3b4`)
- Loupe: removed hardcoded 1000pt override in `refreshLoupePanel` (`45e612c`)

### Compatibility
Page editing (delete / rotate / reorder) writes directly to CBZ or folder sources. CBR / 7z must first be converted to CBZ via the "Convert to CBZ" command.

---

## [1.7.2] and earlier

Pre-changelog. See `git log v1.7.2` for history.
