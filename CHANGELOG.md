# Changelog

All notable changes to Simple Comic. Format roughly follows [Keep a Changelog](https://keepachangelog.com/).

## [1.10.2] - 2026-08-18

### Fixed
- **Deleting pages down to one (or none) crashed the app on the next redraw** (`4f3afec`). `DTPolishedProgressBar` sizes its fill as `width * (currentValue + 1) / maxValue`, and `maxValue` is the *last page index* — 0 for a one-page work, negative once the last page goes. The division by zero produced NaN geometry, `NSBezierPath` raised on it, and AppKit turns an exception thrown inside `-drawRect:` into a crash. A one-page work now simply fills the bar. Found with an `objc_exception_throw` breakpoint after a 300-page CBZ crashed on a 299-page delete.

## [1.10.1] - 2026-08-17

### Fixed
- **Deleting pages still crashed in 1.10.0** (`43ac23e`). The 1.10.0 fix copied `arrangedObjects` before bounds-checking it, but `arrangedObjects` is an `_NSControllerArrayProxy` over the array controller's live mutable array and `-copy` walks it index by index — a delete shrinking it mid-walk threw before the bounds check ever ran (`index 621 beyond bounds [0 .. 620]`, inside `-[__NSPlaceholderArray initWithArray:copyItems:]`). The real problem is reading an `NSArrayController` off the main thread at all, so the controller access now hops to the main queue (`-pageAtIndexFromAnyThread:`, `-livePageCount`) — a direct call when already on main — while the expensive thumbnail decoding stays on the background thread.

## [1.10.0] - 2026-08-17

### Added
- **Invert Selection (⇧⌘I)** — Edit ▸ Invert Selection flips the page multi-selection (`407c079`). While the Thumbnail Exposé is open it inverts the grid selection; otherwise it inverts the paged view's marked set. Makes "delete everything except these few" a two-step job: mark the keepers, invert, delete.

### Fixed
- **Deleting pages (from a zip/CBZ or a folder) crashed the app** (`407c079`). Removing a page fires the `arrangedObjects.@count` KVO that spawns a fresh thumbnail-generation thread, and that thread snapshotted the page count once before looping. A delete shrinking the array mid-loop left it reading an index that no longer existed — `-[__NSArrayM objectAtIndex:] index 51 beyond bounds [0 .. 50]` — and because the throw happened off the main thread nothing caught it, so the app aborted. The page accessors are now bounds-checked, `-processThumbs` re-reads the live count every pass, `threadIdent` hand-off is atomic (one thread is spawned per deleted page), and the thumbnail bar clamps its stale draw limit.
- **Thumbnail Exposé: deleting pages could crash with `EXC_BAD_ACCESS` in the hover preview** (`407c079`). The delayed preview timer held its collection-view item without retaining it; the reload that follows a delete frees the item, and the timer then messaged freed memory. The pending item is retained, dropped together with its timer, cancelled up front on reload, and skipped if it is no longer in the grid.

## [1.9.3] - 2026-06-25

### Fixed
- **⌘-letter shortcuts (⌘C Capture Page, ⌘Q Quit, …) did nothing while a non-Latin input source (e.g. 2-Set Korean / 한글) was active** (`3330cce`). The menu shortcuts are plain Latin key equivalents, but under Hangul `-charactersIgnoringModifiers` returns the composed jamo (e.g. "ㅊ" for the C key), so AppKit never matched the Latin equivalent and the shortcut fell through silently. Arrow/space keys and mouse-driven menu commands were unaffected. ⌘-key events are now re-matched against the menu using the key's Latin character (resolved from the current ASCII-capable keyboard layout), so the shortcuts work regardless of the active input source.

## [1.9.2] - 2026-06-22

### Fixed
- Holding an arrow key while a page is zoomed in / larger than the window no longer spins a runaway timer that pegs the CPU (`10147b4`). The smooth-scroll timer interval was written as `1/10` — integer division, so `0` — which NSTimer clamps to ~0.1 ms (~10 kHz). Fixed to the intended 0.1 s (10 fps) interval. *(This was first thought to also explain the dead ⌘-shortcuts; the real cause of that was the input-source bug fixed in 1.9.3.)*

## [1.9.1] - 2026-06-19

### Fixed
- **⌘Q would not quit the app** when session restore was off and a window had pending "save on close" page edits (rotate/reorder/delete). Termination force-closes each window, which raised a blocking save-changes modal and stalled the quit (`4bad3d2`). The edits are now dropped on quit so the app terminates immediately; the save prompt is unchanged when you close a window manually (⌘W).

## [1.9.0] - 2026-06-14

### Added
- **Marked-page multi-select shared between the paged view and the Thumbnail Exposé** (`e21bc2f`) — a selection made in one mode stays valid in the other:
  - `s` in the paged view toggles the current page's mark. Matched by physical key code (kVK_ANSI_S) so it works while a Hangul (or other non-Latin) input source is active.
  - The paged view shows a `✓ 선택 N` badge while pages are marked, pinned to the visible area (works in fullscreen).
  - The Exposé pre-selects the marked pages on open / reload and writes Cmd/Shift-click changes back.
  - Delete (Exposé Delete/Backspace or Edit ▸ Delete) removes the marked pages via the existing deferred-delete path; deleted pages leave the set, skipped non-CBZ pages stay marked.

## [1.8.1] - 2026-06-07

### Fixed
- Thumbnail Exposé: Cmd/Shift-click to extend the multi-selection no longer pops the large hover preview over the grid (it looked like the click went into a "zoom" mode). The preview is suppressed while a selection modifier is held (`04d6297`).

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
