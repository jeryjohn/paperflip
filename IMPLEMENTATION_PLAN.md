# PaperFlip — Implementation Plan

Execution plan for the migration described in `updateplan.md`, grounded in the
code that actually exists. `updateplan.md` is the *what*; this is the *how*, in
commit-sized order.

**Status:** Phase 0 complete (branch `phase-0-stabilize`, 4 commits). Phase 1
is next. `README.md` is already written against the target API and does not
describe working code.

---

## 0. Decisions needed before Phase 1

These change the work materially. Resolve them first.

| # | Decision | Recommendation |
| --- | --- | --- |
| D1 | Rename package `flip_book` → `paperflip`? The README already assumes it. | **Yes.** Do it in the *same commit* as the `core/pdf/epub` directory move — otherwise all 10 intra-lib imports get rewritten twice. Ship `lib/paperflip.dart` as the barrel and keep `lib/flip_book.dart` as a deprecated re-export. |
| D2 | `PdfSource.file(...)` — `dart:io File` (as the README shows) or `String path`? A `File` breaks web, and `example/` is web-configured. | **`String path`** as the primary factory, plus `PdfSource.ioFile(File)` in an io-only shim. Update the README. |
| D3 | What is the real SDK floor? The pubspec claims Dart ≥3.0.0 / Flutter ≥3.10.0, but `pdfrx ^2.4.4` requires Dart `^3.10.0` / **Flutter ≥3.41.0**. The project pins 3.41.9 via `.fvmrc`, so it builds — the *declared* constraints are simply wrong. | **Declare the truth: Dart `^3.10.0`, Flutter `>=3.41.0`.** Side effect: `flutter_widget_from_html_core`'s Flutter ≥3.32.0 floor is then **free**, so the EPUB renderer costs nothing in SDK terms. Always run via `fvm flutter`. |
| D4 | Does `FlipSettings.direction` ship now? | Declare `FlipDirection` with **only `horizontal`**, assert on anything else. `updateplan.md` §6 says horizontal initially; a half-built vertical axis is worse than none. |
| D5 | Version for the API break. | **0.2.0** — pre-1.0, so a breaking minor is legitimate. `CHANGELOG.md` needs Breaking / Deprecated / Added / Fixed sections with a migration table. |

---

## Phase 0 — Stop the bleeding (no API change) — DONE

Pure bug fixes, shipped as 4 commits. See CLAUDE.md "Bug status" for what
landed and what is still open. Notes on the two items that turned out
differently than planned:

- **`PdfViewerController` is not disposable** — it extends
  `ValueListenable<Matrix4>`, not `ChangeNotifier`, and has no `dispose()`.
  That audit finding was a false positive; nothing to fix.
- **The build was never broken.** The version-solving failure came from
  invoking bare `flutter` (an older default SDK) rather than `fvm flutter`.
  The declared pubspec constraints were still wrong and were corrected.

0. **Correct `pubspec.yaml`** to the real floor (`sdk: ^3.10.0`,
   `flutter: >=3.41.0` — what `pdfrx ^2.4.4` already requires) and replace the
   `yourorg` placeholders. Build commands must use `fvm flutter` (pinned 3.41.9);
   bare `flutter` may pick an SDK too old to resolve.
1. **Fix `goToPage`.** Today it drops every intent after the first and lands on
   page 1. The 16 ms sleep in `flip_book_controller.dart:120` races a 600 ms
   animation. Replace the sleep-and-hope with a real queue: either the controller
   awaits a completer the widget resolves on `reportAnimating(false)`, or the
   widget keeps a `Queue<FlipIntent>` instead of a single slot. The second is
   cleaner and generalises to `EpubController`.
   *This must land before `FlipSettings.enabled`, because `enabled: false` takes
   the instant path and masks the bug.*
2. **Dispose what's leaked.** `PdfDocument` (`flip_book_pdf.dart` — add a
   `dispose()`, and dispose the old doc on source change), `PdfViewerController`
   (`flip_book_reader.dart:105`).
3. **Memoize `_source`** into a field in `flip_book_reader.dart:216` so rebuilds
   don't re-mint a `PdfDocumentRef` and trigger a full PDF reload.
4. **Report page count from the flip path** so the reader's counter, FAB column
   and page-selector stop being dead outside zoom/low-memory mode.
5. **Animation-controller lifecycle.** One long-lived `_settleCtrl` created in
   `initState` instead of per-drag allocation + disposal from inside its own
   status listener. Fix the `_animCtrl`-before-`_curvedAnim` dispose order.
6. **Restore orientation to what the host app had**, not unconditionally to
   portrait (`flip_book_reader.dart:147-150`).
7. **Fix the two lying doc comments** (`flip_book_pdf.dart:36-42` documents
   `PdfDocumentRef.file/.asset/.uri` — those named constructors don't exist).

**Gate:** add `test/` with at least three widget tests before touching the
engine — `goToPage(n)` reaches `n`; a flip settles at exactly 0.0/1.0; the
reader reports a page count in flip mode. There are currently **no tests at
all**, and every behaviour here is otherwise eyeball-only.

---

## Phase 1 — `FlipSettings`

New file `lib/src/core/flip_settings.dart`:

```dart
@immutable
class FlipSettings {
  const FlipSettings({
    this.enabled = true,
    this.duration = const Duration(milliseconds: 600),
    this.curve = Curves.easeInOut,
    this.settleCurve = Curves.easeOut,
    this.direction = FlipDirection.horizontal,
    this.showShadow = true,
    this.showBackFace = true,
  });
  // + copyWith, ==, hashCode  ← load-bearing, see below
}
```

Value equality is **not optional**: `didUpdateWidget` and
`PageFlipPainter.shouldRepaint` both diff on it.

**What it absorbs** (each is a hardcoded value today):

| Value | Location |
| --- | --- |
| `Duration(milliseconds: 600)` | `flip_book_widget.dart:43`, duplicated at `flip_book_pdf.dart:24` |
| `Curves.easeInOut` (flip) | `flip_book_widget.dart:117` |
| `Curves.easeOut` (settle) | `flip_book_widget.dart:286` |
| `clamp(120, 600)` settle cap | `flip_book_widget.dart:279-282` |
| shadow + highlight passes | `page_flip_painter.dart:243,245` |
| back-face | `flip_book_widget.dart:566-572` and `page_flip_painter.dart:290-313` |

Keep `curve` and `settleCurve` **separate**. Applying `easeInOut` to a released
drag eases *in* on a gesture already in motion and reads as a stall.

Derive the settle clamp from `duration`. As written, `clamp(120, 600)` silently
caps any configured duration, so `duration: 1200ms` appears not to work on
drag-release — the most common interaction.

### `enabled: false`

Branch at these points; `enabled: false` means progress never leaves 0 and
commits happen immediately:

- `_onControllerUpdate` (`:148`) — `animate = intent.animate && settings.enabled`.
  This is the main choke point for `flipNext`/`flipPrev`/`goToPage`.
- `_startAnimatedFlip` (`:167`) — early commit, defence in depth.
- `_onPanUpdate` (`:219`) — keep the direction decision, skip writing `_dragProgress`.
- `_onPanEnd` (`:252`) — **trap:** with `_dragProgress` never written,
  `_dragProgress > 0.35` (`:260`) is always false and swipe-to-turn silently
  dies. Stash the raw progress in a separate field written regardless of
  `enabled`, and test *that*.
- `_settleTo` (`:268`) — early `_finishSettle(target)`.

Also handle the mid-flight toggle: flipping `enabled` to false while animating
must stop and commit, not strand a half-turned sheet.

### `showShadow` / `showBackFace`

- `showShadow` gates `page_flip_painter.dart:243,245`. **Add all four colour/flag
  fields to `shouldRepaint` (`:338-341`)** — it currently compares only
  `progress`, `corner`, `isForward`, so a runtime toggle wouldn't repaint.
- `showBackFace: false` must **skip the reflected-front layer**
  (`flip_book_widget.dart:566-572`) and let the painter's `_paintBackFace`
  gradient show through. Do *not* gate `_paintBackFace` itself — that leaves a
  transparent hole in the flap.
- Plumb through `_FlipLayers` (ctor `:515`, fields `:525`, build `:535`) and
  **all three** call sites: `:365` (portrait), `:429` and `:451` (spread).

Then forward `flip:` from `FlipBookPdf` (`:130-147`) and `FlipBookReader`
(`:499-508` — the reader currently exposes no flip config at all), deprecating
`flipDuration` and the dead `hotZoneSize`.

Finally, `controller.setFlipEnabled()` / `setFlipDuration()` per `updateplan.md`
§7: an override channel on the controller, resolved in `build` as
`controller?.settingsOverride ?? widget.flip`, with `_animCtrl.duration` and
`_curvedAnim` re-synced on that path.

**Verify visually:** drag-release at several durations/curves; `showBackFace:
false` showing a gradient not a hole; `showShadow: false` not orphaning the flap
edge stroke; landscape spread both directions at page 0 and `pageCount-1`;
`enabled: false` swipe still turning pages.

---

## Phase 2 — `PageSource`, `PdfSource`, and the `FlipBook` facade

### 2a. `PageSource` — the abstraction both PDF and EPUB need

`FlipBookWidget` takes a fixed `int pageCount` and a *synchronous* `pageBuilder`.
EPUB breaks both: its page count depends on viewport + typography, and its pages
are produced asynchronously. Generalise the boundary now, while PDF is the only
consumer:

```dart
abstract class PageSource extends ChangeNotifier {
  int get pageCount;                 // may change on re-layout; notifies
  bool get isReady;
  void layout(PageLayout layout);    // viewport in → pagination out
  Widget build(BuildContext, int index);   // cheap, cached, never blocks
  void ensure(PageWindow window);    // render these, evict the rest
}
```

Keep `pageCount` + `pageBuilder` as a thin `BuilderPageSource` adapter so
`FlipBook.custom()` and existing users are unaffected — `updateplan.md` §4 names
the page-builder boundary as the thing to preserve.

`PdfPageSource` then fixes three things at once: it owns and **disposes** the
`PdfDocument`; it caps DPI (`min(devicePixelRatio, 2.0)`), turning the reader's
`/proc/meminfo` escape hatch into a tuning knob rather than a whole-viewer
bypass; and because `build(i)` is cache-backed, the `stationary` and
`turningFront` slots (`flip_book_widget.dart:374,376`) resolve to the **same**
cached image instead of two live `PdfPageView`s — removing one full page bitmap
per flip. Add `RepaintBoundary` around each `_FlipLayers` child.

### 2b. `PdfSource`

Sealed class in `lib/src/pdf/pdf_source.dart` with `.file(String path)`,
`.asset()`, `.uri()`, `.data()`, `.fromRef()` as an escape hatch, an `@internal
toRef()`, and **value equality** — which is what actually fixes the
reload-on-rebuild hazard regardless of pdfrx's own equality semantics.

This is the one unavoidable break: `FlipBookPdf.source` changes type from
`PdfDocumentRef` to `PdfSource` and Dart has no overloads.

### 2c. The facade

`lib/src/flip_book.dart` — a `StatelessWidget` with named constructors `.pdf()`,
`.custom()`, `.epub()` and a private mode discriminator, delegating to the
existing widgets. Named constructors, not static methods returning `Widget` —
static methods lose `const` (and `prefer_const_constructors` is enforced) and
make the widget untypeable in tests. `.epub()` can be declared now and throw
`UnimplementedError` until Phase 4.

Place it **above** `core/` and `pdf/`, not inside `core/`, or core ends up
depending on pdf.

### 2d. The move + rename

One commit: `src/{core,pdf}/` split, `flip_book` → `paperflip`, 10 intra-lib
imports, 7 barrel exports, `pubspec.yaml` name + the `yourorg` placeholders.
`example/lib/main.dart` imports only the barrel, so it needs a one-line change.

**Add a PDF example** — `FlipBookPdf` and `FlipBookReader` currently have zero
example coverage, so the whole migration is untested by the demo.

---

## Phase 3 — EPUB prototype (standalone, before integration)

**Do this outside the flip engine first.** `updateplan.md` §15 is right to
prototype separately, and the research below narrows what to prototype.

### The constraint that eliminates most options

`RepaintBoundary.toImage` renders platform views **blank** on Android and throws
on iOS; on web a WebView is an `<iframe>` composited outside the Flutter canvas.
So **no WebView-backed EPUB engine can be composited into a finger-following
curl.** That rules out epub.js-in-WebView, `flutter_epub_viewer`,
`vocsy_epub_viewer`, and Readium's native navigators — `flutter_readium` exposes
a platform view wrapping a WKWebView, not page bitmaps. (`flutter_readium` also
requires Flutter ≥3.44.8 and drops desktop.)

The `takeScreenshot` escape hatch returns PNG bytes per frame — fine for a
discrete "flip now" button, hopeless at 60 fps.

### Chosen stack

| Layer | Choice | Verified |
| --- | --- | --- |
| Parse | `epub_plus` 5.1.0 | Dart ≥3.0, web+wasm, published 2025-11-03 |
| Render | `flutter_widget_from_html_core` 0.17.4 | Dart ≥3.4.0, **Flutter ≥3.32.0**, published 2026-09-08 |
| Paginate | own code | neither renderer has any pagination API |

`flutter_html` is effectively abandoned (last push 2025-03-12, an unanswered
"is this discontinued?" issue) — don't build on it.

Budget ~half a day to patch `epub_plus`'s EPUB-3 nav bugs, which every fork in
the `dart-epub` lineage shares verbatim: `properties == 'nav'` is an exact
compare against a space-separated attribute; it takes the *first* `<nav>` rather
than the `epub:type="toc"` one; `findElements('ol').single` throws on 0 or 2+;
and there is no NCX fallback, so a malformed v3 nav hard-throws.

### Pagination approach

Start with **clip-and-translate**: build the chapter once at viewport width,
measure total height, then page *n* is `ClipRect` + `OverflowBox` +
`Transform.translate(0, -n*H)`. Reflow falls out for free — re-layout at a new
font size gives a new height gives a new page count. ~100 lines, full CSS
fidelity on day one.

Then **rasterize each page once to a `ui.Image`** and hand `RawImage` to
`pageBuilder`. This is legal precisely because the content is pure Flutter, and
it is what makes the engine's 3–4-subtrees-per-frame cost collapse.

Upgrade seam handling later (snap offsets to line boundaries via
`computeLineMetrics`) without changing the public API.


Two hard constraints:
- **`TextPainter` cannot run in a background isolate** (open Flutter issue since
  2019). Chunk pagination across frames with a per-frame budget *from the start*.
- **A locator is spine index + character offset (or CFI), never a page index.**
  Page indices are invalid by definition the moment anything reflows.

Worth reading before writing paginator code: `HQLiLi/flutter-epub-reader`
documents hitting near-O(n²) binary-split pagination — 8,454 node measurements
for a 1,629-paragraph chapter. `flutter_book_reader` is an existence proof for
the architecture (real `TextPainter` pagination + position preserved across
font-size changes + its own curl) but handles plain text, not HTML.

### Keep the engine swappable

```dart
abstract class EpubPaginationEngine {
  Future<void> open(EpubSource source);
  EpubToc get toc;
  int get pageCount;
  Widget buildPage(BuildContext, int index, BoxConstraints);
  Future<void> applySettings(EpubReaderSettings s);
  EpubLocator locatorForPage(int index);
  int pageForLocator(EpubLocator l);
  bool get supportsCurl;   // ← design this in now
}
```

`supportsCurl` is the retrofit you cannot afford to skip: a WebView fallback
engine can implement everything *except* `buildPage`, and `FlipBook.epub()` needs
to read the flag to pick a non-curl slide transition rather than ship a broken
curl.

---

## Phases 4–8 — EPUB integration

4. **Pagination against the real viewport.** `EpubPageSource implements
   PageSource`; `layout()` triggers re-pagination, `pageCount` changes and
   notifies. Because Phase 2a generalised the boundary, **the flip engine needs
   no changes here.**
5. **Reflow / "zoom".** `setFontSize` / `setLineHeight` / `setMargin` →
   re-paginate → map the stored locator back to a page index. The central rule
   from `updateplan.md`: *EPUB zoom is reflow, not page scaling.* The page never
   exceeds the viewport; there is no pan.
6. **`EpubController`**, separate from `FlipBookController` — chapter nav, TOC,
   typography. Note `FlipBookController.pendingIntent` currently leaks the
   private `_FlipIntent`; that must become internal-public before a second
   controller can drive the widget.
7. **Navigation + position persistence.** TOC, chapter jumps, reading progress,
   restore-last-position.
8. **Orientation.** Rotation re-paginates and restores position; verify the
   double-page spread, which is the least battle-tested geometry and has two of
   the three `_FlipLayers` call sites.

## Phase 9 — Docs

Split `README.md` into "Today (0.2.x)" documenting what ships, and a clearly
labelled "Planned" section for anything that doesn't. Right now it documents
only aspirational API, which leaves the 0.2.0 migration with no "before" state
to migrate from. It also references `LICENSE`, `docs/images/` and
`example/assets/`, none of which exist — add them or drop the references.

`FlipBookReader`, `PageSelectorDialog`, `FlipCorner` and the low-memory/zoom
fallback are documented nowhere. `nextPage()`/`previousPage()` are shown as the
navigation verbs but are the **non-animated** variants; the animated
`flipNext()`/`flipPrev()` are undocumented.

---

## Sequencing summary

```text
Phase 0  bug fixes + first tests        ← independently shippable
Phase 1  FlipSettings                    ← 0.2.0 starts here
Phase 2  PageSource + PdfSource + facade + rename/move
   ─── ship 0.2.0 ───
Phase 3  EPUB prototype, standalone      ← D3 (SDK floor) binds here
Phase 4-8 EPUB integration
   ─── ship 0.3.0 ───
```

Phases 0–2 touch only existing code and carry no new dependencies. Phase 3 is
the first commitment of new dependencies and a raised SDK floor, and it is
deliberately a standalone prototype so that commitment stays reversible.
