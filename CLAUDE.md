# CLAUDE.md

Guidance for working in this Flutter package.

## Read this first: the repo is mid-migration

The package is **named `flip_book` in code** (`pubspec.yaml`, `lib/flip_book.dart`,
every `package:flip_book/src/...` import) but is **being renamed to `paperflip`**
and re-architected from "PDF page-flip widget" into a general document/book
reader engine (PDF + EPUB + custom widgets behind one flip engine).

`README.md` has **already been rewritten against the target API** — `FlipBook.pdf/.epub/.custom`,
`FlipSettings`, `PdfSource`, `package:paperflip/paperflip.dart`. **None of that
exists in `lib/` yet.** Treat the README as a spec, not as documentation. Do not
"fix" code to match it piecemeal; follow `IMPLEMENTATION_PLAN.md`, which sequences
the change.

- `updateplan.md` — the product vision (author's, do not rewrite).
- `IMPLEMENTATION_PLAN.md` — the code-grounded execution plan. Start here.

### Always use `fvm flutter`, never bare `flutter`

This project pins Flutter **3.41.9** via `.fvmrc` (Dart 3.11.5). The bare
`flutter` on PATH may resolve to a different default (e.g. `~/fvm/default`),
and an older SDK fails outright at version solving:

```text
Because flip_book depends on pdfrx >=2.3.0 which requires Flutter SDK
version >=3.41.0, version solving failed.
```

That error means the wrong SDK, **not** a broken repo. `fvm flutter pub get`
and `fvm flutter analyze lib/` both succeed on the pinned version.

Related real defect: `pubspec.yaml` declares `sdk: >=3.0.0 <4.0.0` /
`flutter: >=3.10.0`, but `pdfrx ^2.4.4` requires Dart `^3.10.0` /
Flutter `>=3.41.0`. The declared floor is fiction and should be corrected to
match. (`pdfrx` raised its floor at 2.3.0 — 2.2.24 was the last Flutter ≥3.35.1
release, and 2.5.0 raises it again to ≥3.47.0.)

## Layout (current, on disk)

| File | Role |
| --- | --- |
| `lib/flip_book.dart` | Public barrel — the only thing consumers import. |
| `lib/src/flip_book_widget.dart` | `FlipBookWidget` — core flip engine. Builds pages on demand, handles gestures + animation, stacks the curl layers (`_FlipLayers`). |
| `lib/src/flip_book_controller.dart` | `FlipBookController` (a `ChangeNotifier`) — programmatic flips via an intent queue the widget consumes. |
| `lib/src/page_flip_painter.dart` | `PageFoldGeometry` (fold math, shared by widget + painter) and `PageFlipPainter` (shadow / back-face / crease shading). |
| `lib/src/flip_corner.dart` | `FlipCorner` enum + hot-corner hit-testing helpers. |
| `lib/src/flip_book_pdf.dart` | `FlipBookPdf` — wraps `FlipBookWidget`, rendering PDF pages via `pdfrx`. |
| `lib/src/flip_book_reader.dart` | `FlipBookReader` — full-screen reader (app bar, controls, zoom, jump-to-page, low-memory fallback). |
| `lib/src/page_selector_dialog.dart` | `PageSelectorDialog` — grid dialog used by the reader. |
| `example/lib/main.dart` | Demo. Uses **only** `FlipBookWidget` + `FlipBookController` — the PDF widgets have zero example coverage. |

## Layout (target, after the `core/` split)

```text
lib/paperflip.dart            barrel (lib/flip_book.dart kept as deprecated re-export)
lib/src/flip_book.dart        the FlipBook facade (.pdf/.epub/.custom)
lib/src/core/                 flip_book_widget, flip_book_controller, page_flip_painter,
                              flip_corner, flip_settings, page_source
lib/src/pdf/                  flip_book_pdf, flip_book_reader, page_selector_dialog,
                              pdf_source, pdf_page_source
lib/src/epub/                 epub_source, epub_document, epub_renderer,
                              epub_pagination, epub_controller, epub_reader_settings
```

The facade lives at `lib/src/flip_book.dart`, **above** `core/` and `pdf/`, not
inside `core/` — otherwise core depends on pdf and the layering inverts.

## Architecture notes

**Three public widget tiers**, lowest to highest:

1. `FlipBookWidget` — bring-your-own page content via `pageBuilder`.
2. `FlipBookPdf` — same flip mechanics, pages sourced from a `PdfDocumentRef`.
3. `FlipBookReader` — opinionated full-screen screen. **Every parameter is
   optional** (deliberate). On low-RAM Android (≤3 GB by default, read from
   `/proc/meminfo`) and while zooming it falls back to `pdfrx`'s plain
   `PdfViewer` instead of the flip viewer.

`FlipBook.pdf/.epub/.custom` will be a thin facade over these, not a replacement.
Keep the lower tiers exported.

**Controller is intent-based.** `FlipBookController` doesn't mutate the widget
directly — it enqueues a `_FlipIntent` and `notifyListeners()`. The widget reads
`pendingIntent`, acts, then calls `clearIntent()`, and reports state back via
`reportPage` / `reportAnimating`.

Intents are a **queue**, not a single slot (a single slot silently dropped every
intent after the first, which is what broke `goToPage`). Two invariants to keep
when adding controller methods:

- The widget dequeues an intent when it *starts* a flip, so the controller
  tracks that in-flight target separately (`_projectedPage`). Anything that
  computes "the next page" must step from there, not from `currentPage`.
- `_drainIntents` is re-entrancy-guarded. Committing a flip notifies the
  controller, which re-enters the drain; without the guard the nested call
  starts a flip that the outer `_animCtrl.reset()` then kills, stalling the
  queue permanently.

**The flip is rendered as stacked live layers, not a snapshot.** During a turn
`_FlipLayers` stacks (bottom→top): the revealed page, the stationary part of the
current page (clipped to `stationaryPath`), the curl shading (`PageFlipPainter`),
and the turning page's front reflected onto the flap (clipped to `flapPath`,
transformed by `flapReflection`). `PageFoldGeometry` is the single source of
truth for the crease/flap geometry so the clipped content and painted lighting
always agree — change geometry there, not in two places.

**Cost of that design:** 3–4 live page subtrees per frame mid-flip, and the
turning sheet is built **twice** (`stationary` and `turningFront` are the same
index in two Stack slots). For PDF that means two rasterizations of one page.
This is the motivation for the `PageSource` cache described in the plan.

**Page indexing during a flip** (`_buildSinglePage`): a flip always turns one
sheet whose front is `baseIndex` and the page revealed beneath is `baseIndex+1`.
Forward → `baseIndex = currentPage`; backward → `baseIndex = currentPage-1`.

**Gestures (`flip_book_widget.dart`):** a horizontal swipe *anywhere* drives a
flip (swipe left → next, right → previous); start-Y picks top vs. bottom corner.
On release, `_settleTo(target)` runs **one** controller (`_settleCtrl`) that
animates progress to exactly `0.0` or `1.0`, then commits — so a flip can never
rest mid-turn. A fast fling also completes the flip. Two animation controllers
exist (`_animCtrl` for button flips, `_settleCtrl` for drag settling), hence
`TickerProviderStateMixin` (not `Single...`). The 60px `hotZoneSize` is legacy,
**dead** — nothing reads it. Don't carry it into new API.

## Bug status

### Fixed in Phase 0 (do not "re-fix" these)

| Was | Fix |
| --- | --- |
| `goToPage(n)` landed on page 1 — one intent slot, intents enqueued every 16 ms against 600 ms animations, all but the first dropped. | `FlipBookController` holds a `Queue<_FlipIntent>`; the widget drains one flip at a time via `_drainIntents`, resuming from `_onAnimStatus` / `_finishSettle`. Draining is re-entrancy-guarded, and `_onAnimStatus` resets *before* committing. |
| `goToPage`'s future never resolved for instant jumps. | The journey completer is created before `_enqueue` notifies. |
| `flipNext`/`nextPage` collapsed rapid repeated calls onto one page. | They step from `_projectedPage` (end of queue, including the in-flight flip). **Behaviour change:** three taps now turn three pages. |
| `PdfDocument` leaked on every teardown and source change. | `_FlipBookPdfState.dispose()` releases it; a load-generation counter stops a stale load overwriting a newer one. |
| Reader re-minted a `PdfDocumentRef` per build, retriggering full PDF loads. | `_source` is memoised per distinct source key. |
| Page counter / FABs / page-selector were dead in flip mode. | `FlipBookPdf.onDocumentLoaded` reports the count; the reader listens to the flip controller for the current page. |
| Reader forced portrait-only orientation on the host app at dispose. | Passes an empty list, handing control back to the platform manifest. |
| `_settleCtrl` was allocated per drag and disposed inside its own status listener; `dispose()` tore down `_animCtrl` before `_curvedAnim`. | One long-lived settle controller created in `initState`; curved animations disposed before their parents. Easing and duration formula unchanged. |
| `FlipBookPdf.source` doc comment advertised `PdfDocumentRef.file/.asset/.uri/.data`. | Corrected to the real `PdfDocumentRefFile/Asset/Uri/Data` classes. |

### Still open

| Issue | Where |
| --- | --- |
| **`_curvedAnim` is built once and never rebuilt**; `didUpdateWidget` syncs only `duration`. Blocks a configurable `curve` — fix as part of `FlipSettings`. | `flip_book_widget.dart` `initState` / `didUpdateWidget` |
| **`PageFlipPainter.shouldRepaint` ignores its colour fields** (`shadowColor`, `pageBackColor`, `highlightColor`). Any runtime toggle of them won't repaint — must be fixed before `showShadow`/`showBackFace` become configurable. | `page_flip_painter.dart` `shouldRepaint` |
| **The settle duration `clamp(120, 600)` silently caps any configured flip duration**, so `FlipSettings(duration: 1200ms)` will appear not to work on drag-release. Derive the clamp from the setting. | `flip_book_widget.dart` `_settleTo` |
| **`pendingIntent` still returns the private `_FlipIntent`** (`library_private_types_in_public_api`). Must become internal-public before a second controller (EPUB) can drive the widget. | `flip_book_controller.dart` |
| **`pdfrx` marks `loadDocument()` legacy**, recommending `resolveListenable()` / `PdfDocumentListenable.document`, which also gives document sharing and auto-dispose. Worth adopting when `PdfPageSource` lands in Phase 2. | `flip_book_pdf.dart` |

## EPUB: the decision that constrains everything

**EPUB pages must be pure Flutter widgets.** `RepaintBoundary.toImage` renders
platform views (WebView) **blank** on Android and throws on iOS, and on web a
WebView is an `<iframe>` composited outside the Flutter canvas entirely. So
**no WebView-backed EPUB engine can be composited into the page curl** — that
rules out epub.js-in-WebView, `flutter_epub_viewer`, `vocsy_epub_viewer`, and
Readium's native navigators (`flutter_readium` exposes a platform view wrapping
a WKWebView, not page bitmaps).

Chosen stack for the prototype:

- **Parse:** `epub_plus` 5.1.0 (Dart ≥3.0, web+wasm). Budget ~half a day to patch
  its EPUB-3 nav bugs — `properties == 'nav'` is an exact compare against a
  space-separated attribute, it takes the *first* `<nav>` rather than the
  `epub:type="toc"` one, and there is no NCX fallback. Every fork in the
  `dart-epub` lineage (`epubx`, `epub_pro`) shares these verbatim.
- **Render:** `flutter_widget_from_html_core` 0.17.4. Needs Dart ≥3.4.0 /
  Flutter ≥3.32.0 — **free**, since `pdfrx` already forces a higher floor
  (Flutter ≥3.41.0). (`flutter_html` is effectively abandoned: last push
  2025-03-12, an unanswered "is this discontinued?" issue.)
- **Paginate:** own code. Neither renderer has any pagination API. Start with
  clip-and-translate (build the chapter once at viewport width, then
  `ClipRect` + `OverflowBox` + `Transform.translate(0, -n*H)`), then rasterize
  each page once to a `ui.Image` and hand `RawImage` to `pageBuilder` — which is
  also what makes the 3–4-layers-per-frame cost disappear.

Two hard constraints to design around from day one:

1. **`TextPainter` cannot run in a background isolate** (open Flutter issue since
   2019). All measurement is on the UI isolate → chunk pagination across frames.
2. **A locator is spine index + character offset (or CFI), never a page index.**
   Page indices are invalid by definition the moment anything reflows.

Keep the engine behind an internal `EpubPaginationEngine` interface with a
`bool get supportsCurl` capability flag, so a WebView fallback engine can ship
later as a non-curl "slide" mode rather than a broken curl.

**PDF stays fixed-layout.** Never introduce font reflow / line-height / margin
controls into the PDF path.

## EPUB implementation notes

`lib/src/epub/` is a working prototype: `EpubSource` -> `EpubDocument` ->
measure -> `EpubPagination` -> pages fed to `FlipBookWidget`.

**Reading order is the spine, never `book.chapters`.** `epub_plus` exposes
`chapters` as the flattened NCX table of contents, where several entries
commonly point at the *same* file and each returns that whole file's content.
Paginating off it renders the same text repeatedly. `EpubDocument` takes order
from the spine (manifest id -> href -> content) and reduces the TOC to labelled
pointers into it.

**`HtmlWidget` must be built with `buildAsync: false`.** Its async path shows a
placeholder on the first frames; measurement then records the *placeholder's*
height (~52px) for every chapter, so the whole book paginates to one near-empty
page each. This fails silently — the book renders, it is just wrong.

**Pagination measures one document per frame.** `TextPainter` cannot run off
the UI isolate, so a whole-book pass would block for as long as laying out every
chapter takes. `_MeasureHost` lays a document out inside a `SingleChildScrollView`
(which grants unbounded height) and reads its natural height back after layout.

**A position is an `EpubLocator`** — spine index plus progress through that
document — never a page number, which is invalid the moment anything reflows.
Re-pagination stashes the locator, rebuilds, then restores.

**Known gaps:** each page currently rebuilds its whole chapter's HTML, and the
curl stacks 3-4 page layers per frame; the planned fix is rasterising each page
once to a `ui.Image` and handing `RawImage` to `pageBuilder`. Page seams can cut
a line in half (the clip-and-translate tradeoff). The test corpus is three
EPUB 2.0 books with NCX nav, so the EPUB 3 `nav.xhtml` path -- where `epub_plus`
has real bugs -- is completely uncovered.

## Conventions

- **Imports inside `lib/`:** use `package:flip_book/src/...` form, NOT relative
  (`always_use_package_imports` is enforced). Barrel *exports* are relative and
  that's fine — the lint doesn't cover exports. When the package is renamed,
  do the directory move and the rename in **one** commit or you rewrite all
  10 intra-lib imports twice.
- Several strict lints are on (`prefer_const_constructors`, `unawaited_futures`,
  `avoid_print`, `sort_pub_dependencies`, …) — match them. `prefer_const_constructors`
  means new config objects like `FlipSettings` must be `const`-constructible.
- Any new value type that a widget diffs on (`FlipSettings`, `PdfSource`) needs
  `==`/`hashCode`/`copyWith`. `didUpdateWidget` and `shouldRepaint` depend on it —
  value equality is load-bearing, not a nicety.
- Keep public widgets' params optional where it makes sense; `FlipBookReader` is
  intentionally all-optional.
- Doc-comment public API with `///` and a short `dart` example — and verify the
  example compiles; two existing doc comments document API that doesn't exist.
- `pdfrx` API moves fast: `PdfViewerParams.maxScale` is deprecated — use
  `sizeDelegateProvider: PdfViewerSizeDelegateProviderLegacy(maxScale: ...)`.
  Load a document via `PdfDocumentRef.loadDocument(progressCallback)` (there is
  no `resolveDocument`). Sources: `PdfDocumentRefUri/Asset/File`.
- Don't let pdfrx types leak into the public API — `PdfSource.toRef()` stays
  `@internal`.

## Commands

This package is not web-configured; only `example/` is. Run / build from there.

```bash
fvm flutter analyze lib/                 # from package root — must be clean
fvm flutter test                         # widget tests
fvm dart format lib/ test/
cd example && fvm flutter run -d chrome  # run the demo (or -d windows)
cd example && fvm flutter build web --debug --no-wasm-dry-run
```

Notes:

- **`fvm` prefix is required** — see above. Bare `flutter` may pick the wrong SDK.
- Baseline `analyze` is **3 info-lints**, all in `flip_book_controller.dart`
  (listed below). Anything beyond that is new and must be fixed.
- `flutter analyze` from the package root works; `flutter run`/`build` need
  `example/` as the working dir (the root has no `lib/main.dart`).
- `flutter run` is interactive (reads `r`/`R`/`q` from stdin); it can't be
  hot-restarted from a non-interactive shell — relaunch to pick up changes.
- Pre-existing info-lints remain in `flip_book_controller.dart`
  (`library_private_types_in_public_api`, `unnecessary_overrides`,
  `type_init_formals`) — leave them unless asked; don't let new code add lints.
  The first one is `pendingIntent` returning the private `_FlipIntent`; it must
  become internal-public before a second controller (EPUB) can drive the widget.

## Gotchas

- `test/` has 25 widget tests covering controller navigation, drag settling and
  lifecycle. Run with `fvm flutter test`. **Never `await` a library future
  directly inside `testWidgets`** — if it never completes the test hangs
  forever instead of failing. Track completion with a flag and assert on it
  after pumping (see `_track` in `flip_book_controller_test.dart`).
- **Do not run `dart format` across `lib/`.** Dart 3.11's formatter reflows the
  existing code heavily, burying real changes in unrelated churn and adding new
  `curly_braces_in_flow_control_structures` lints. Format new files only.
- Landscape (double-page spread) flip geometry is less battle-tested than
  portrait — there are **three** `_FlipLayers` call sites (one portrait, two
  spread), so any layer change must be made in all three. Verify visually.
- The low-memory probe only does anything on Android; elsewhere it defaults to
  the flip viewer.
- `homepage`/`repository` in `pubspec.yaml` are placeholders (`yourorg`).
- `README.md` references `LICENSE`, `docs/images/` and `example/assets/` — **none
  of which exist**.
- A settle-duration `clamp(120, 600)` silently caps any configured flip duration,
  so `FlipSettings(duration: 1200ms)` will appear not to work on drag-release
  (the most common interaction) unless the clamp is derived from the setting.
