# CLAUDE.md

Guidance for working in the `flip_book` Flutter package.

## What this is

A Flutter **package** (not an app) providing a realistic book page-flip widget
with drag-to-curl animation, programmatic control, PDF rendering, and a
ready-made full-screen PDF reader. Published API lives in `lib/flip_book.dart`;
implementation in `lib/src/`. The runnable demo is in `example/`.

- Min SDK: Dart `>=3.0.0 <4.0.0`, Flutter `>=3.10.0`.
- Sole runtime dependency: `pdfrx` (`^2.4.4`) for PDF rendering.

## Layout

| File | Role |
| --- | --- |
| `lib/flip_book.dart` | Public barrel — the only thing consumers import. Exports everything below. |
| `lib/src/flip_book_widget.dart` | `FlipBookWidget` — core flip engine. Builds pages on demand, handles gestures + animation, stacks the curl layers (`_FlipLayers`). |
| `lib/src/flip_book_controller.dart` | `FlipBookController` (a `ChangeNotifier`) — programmatic flips via an intent queue the widget consumes. |
| `lib/src/page_flip_painter.dart` | `PageFoldGeometry` (fold math, shared by widget + painter) and `PageFlipPainter` (shadow / back-face / crease shading). |
| `lib/src/flip_corner.dart` | `FlipCorner` enum + hot-corner hit-testing helpers. |
| `lib/src/flip_book_pdf.dart` | `FlipBookPdf` — wraps `FlipBookWidget`, rendering PDF pages via `pdfrx`. |
| `lib/src/flip_book_reader.dart` | `FlipBookReader` — full-screen reader (app bar, controls, zoom, jump-to-page, low-memory fallback). |
| `lib/src/page_selector_dialog.dart` | `PageSelectorDialog` — grid dialog used by the reader. |
| `example/lib/main.dart` | Demo wiring `FlipBookWidget` + `FlipBookController`. |

## Architecture notes

**Three public widget tiers**, lowest to highest:
1. `FlipBookWidget` — bring-your-own page content via `pageBuilder`.
2. `FlipBookPdf` — same flip mechanics, pages sourced from a `PdfDocumentRef`.
3. `FlipBookReader` — opinionated full-screen screen. **Every parameter is
   optional** (deliberate — supply `pdfUrl`/`pdfAssetPath`/`pdfFilePath` or it
   shows an empty-source message). On low-RAM Android (≤3 GB by default, read
   from `/proc/meminfo`) and while zooming it falls back to `pdfrx`'s plain
   `PdfViewer` instead of the flip viewer.

**Controller is intent-based.** `FlipBookController` doesn't mutate the widget
directly — it enqueues a `_FlipIntent` and `notifyListeners()`. The widget reads
`pendingIntent`, acts, then calls `clearIntent()`. The widget reports state back
via `reportPage` / `reportAnimating`. Keep this one-pending-intent contract when
adding controller methods.

**The flip is rendered as stacked live layers, not a snapshot.** During a turn
`_FlipLayers` stacks (bottom→top): the revealed page, the stationary part of the
current page (clipped to `stationaryPath`), the curl shading (`PageFlipPainter`),
and the turning page's front reflected onto the flap (clipped to `flapPath`,
transformed by `flapReflection`). `PageFoldGeometry` is the single source of
truth for the crease/flap geometry so the clipped content and painted lighting
always agree — change geometry there, not in two places.

**Page indexing during a flip** (`_buildSinglePage`): a flip always turns one
sheet whose front is `baseIndex` and the page revealed beneath is `baseIndex+1`.
Forward → `baseIndex = currentPage`; backward → `baseIndex = currentPage-1`.

**Gestures (`flip_book_widget.dart`):** a horizontal swipe *anywhere* drives a
flip (swipe left → next, right → previous); start-Y picks top vs. bottom corner.
On release, `_settleTo(target)` runs **one** controller (`_settleCtrl`) that
animates progress to exactly `0.0` or `1.0`, then commits — so a flip can never
rest mid-turn. A fast fling also completes the flip. Two animation controllers
exist (`_animCtrl` for button flips, `_settleCtrl` for drag settling), hence
`TickerProviderStateMixin` (not `Single...`). The 60px `hotZoneSize` is legacy
and no longer gates drag start.

## Conventions

- **Imports inside `lib/`:** use `package:flip_book/src/...` form, NOT relative
  (`always_use_package_imports` is enforced in `analysis_options.yaml`). Several
  other strict lints are on (`prefer_const_constructors`, `unawaited_futures`,
  `avoid_print`, `sort_pub_dependencies`, …) — match them.
- Keep public widgets' params optional where it makes sense; `FlipBookReader` is
  intentionally all-optional.
- Doc-comment public API with `///` and a short `dart` example, as existing files do.
- `pdfrx` API moves fast: `PdfViewerParams.maxScale` is deprecated — use
  `sizeDelegateProvider: PdfViewerSizeDelegateProviderLegacy(maxScale: ...)`.
  Load a document via `PdfDocumentRef.loadDocument(progressCallback)` (there is
  no `resolveDocument`). Sources: `PdfDocumentRefUri/Asset/File`.

## Commands

This package is not web-configured; only `example/` is. Run / build from there.

```bash
flutter analyze lib/                 # from package root — must be clean
cd example && flutter run -d chrome  # run the demo (or -d windows)
cd example && flutter build web --debug --no-wasm-dry-run
```

Notes:
- `flutter analyze` from the package root works; `flutter run`/`build` need
  `example/` as the working dir (the root has no `lib/main.dart`).
- `flutter run` is interactive (reads `r`/`R`/`q` from stdin); it can't be
  hot-restarted from a non-interactive shell — relaunch to pick up changes.
- Pre-existing info-lints remain in `flip_book_controller.dart`
  (`library_private_types_in_public_api`, `unnecessary_overrides`,
  `type_init_formals`) — leave them unless asked; don't let new code add lints.

## Gotchas

- There are **no tests** yet (`flutter_test` is wired but unused).
- `homepage`/`repository` in `pubspec.yaml` are placeholders (`yourorg`).
- The low-memory probe only does anything on Android; elsewhere it defaults to
  the flip viewer.
- Landscape (double-page spread) flip geometry is less battle-tested than
  portrait — verify visually when touching `_buildSpread`.
