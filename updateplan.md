# PaperFlip — EPUB & Reader Engine Update Plan

## 1. Goal

Evolve `paperflip` from a primarily PDF page-flip widget into a reusable Flutter document/book reader engine that supports:

- `FlipBook.pdf()`
- `FlipBook.epub()`
- `FlipBook.custom()`

All three should use the same core page-flip engine.

The key EPUB feature is **reflowable reading with zoom-like font scaling**, not traditional canvas zoom. Increasing the reading size should re-paginate the EPUB so the content remains inside the screen and the user does not need to horizontally/vertically pan a giant page.

---

# 2. Target Public API

## PDF

```dart
FlipBook.pdf(
  source: PdfSource.file(file),
  controller: controller,
  flip: FlipSettings(
    enabled: true,
    duration: Duration(milliseconds: 450),
  ),
)
```

PDF remains fixed-layout.

Do not introduce EPUB-style font reflow into the PDF renderer.

---

## EPUB

```dart
FlipBook.epub(
  source: EpubSource.file(book),
  controller: controller,
  flip: FlipSettings(
    enabled: true,
    duration: Duration(milliseconds: 450),
  ),
  reader: EpubReaderSettings(
    fontSize: 18,
    margin: 20,
    lineHeight: 1.5,
  ),
)
```

EPUB should support:

- EPUB parsing
- HTML/CSS rendering
- Reflowable text
- Pagination
- Font scaling
- Line-height changes
- Margins
- Themes
- Chapter navigation
- Table of contents
- Reading-position preservation
- Portrait/landscape re-pagination

---

## Custom Pages

Keep the generic page-flip capability:

```dart
FlipBook.custom(
  pages: pages,
  flip: FlipSettings(
    enabled: true,
  ),
)
```

This allows developers to use PaperFlip without PDF or EPUB.

---

# 3. Core Architecture

```text
                         FlipBook
                            |
             +--------------+--------------+
             |              |              |
          .pdf()         .epub()        .custom()
             |              |              |
             v              v              v
           pdfrx       EPUB Engine      Flutter
             |              |            Widgets
             |       +------+------+
             |       |             |
             |    Reflow       Pagination
             |       |             |
             +-------+-------------+
                     |
                     v
              FlipBook Core
                     |
              FlipBookWidget
                     |
              PageFlipPainter
                     |
                  Page Curl
```

### Principle

Document-specific code must not be responsible for page-flip animation.

The document layer produces viewport-sized pages.

The core layer handles:

- Page transitions
- Curl physics
- Shadows
- Back-face rendering
- Page dragging
- Animation
- Page navigation
- Portrait/landscape page presentation

---

# 4. Current Codebase to Preserve

The current `paperflip` implementation already has the right foundation.

Preserve and improve rather than rewrite:

- `FlipBookWidget`
- `FlipBookController`
- `PageFlipPainter`
- Page builder architecture
- Page curl animation
- Corner dragging
- Shadows
- Back-face rendering
- Portrait/landscape behavior
- Existing PDF implementation using `pdfrx`

The generic page builder should remain the boundary between document rendering and page-flip behavior.

---

# 5. Refactor the Public API

Move toward:

```text
FlipBook.pdf()
FlipBook.epub()
FlipBook.custom()
```

Instead of making `FlipBookPdf` and `FlipBookEpub` the primary public API.

Internally, separate implementations can still exist.

Example:

```text
FlipBook.pdf()
    -> internal PDF implementation

FlipBook.epub()
    -> internal EPUB implementation

FlipBook.custom()
    -> generic FlipBook implementation
```

---

# 6. Flip Settings

Create a common configuration object:

```dart
FlipSettings(
  enabled: true,
  duration: Duration(milliseconds: 500),
  curve: Curves.easeOut,
  direction: FlipDirection.horizontal,
  showShadow: true,
  showBackFace: true,
)
```

## Initial properties

### `enabled`

```dart
enabled: true
```

Normal page curl.

```dart
enabled: false
```

Page changes without the curl animation.

### `duration`

Allow developers to control animation speed.

### `curve`

Allow animation curve customization.

### `direction`

Allow horizontal page direction initially.

### `showShadow`

Enable/disable page shadows.

### `showBackFace`

Enable/disable the back side of the page.

Do not implement unnecessary effects until the core API is stable.

---

# 7. Flip Controller

Keep a controller for common page operations:

```dart
final controller = FlipBookController();
```

Common API:

```dart
controller.nextPage();
controller.previousPage();
controller.goToPage(20);
```

Also expose flip behavior:

```dart
controller.setFlipEnabled(false);

controller.setFlipDuration(
  Duration(milliseconds: 300),
);
```

The controller should remain focused on page-flip/navigation responsibilities.

---

# 8. EPUB Controller

Do not put every EPUB-specific operation into the common controller.

Create an EPUB-specific controller where necessary:

```dart
final epubController = EpubController();
```

Possible API:

```dart
epubController.zoomIn();
epubController.zoomOut();

epubController.setFontSize(20);
epubController.setLineHeight(1.6);
epubController.setMargin(24);

epubController.nextChapter();
epubController.previousChapter();

epubController.goToChapter(5);
```

---

# 9. EPUB "Zoom" Behavior

This is the most important feature.

EPUB zoom should **not** behave like PDF/canvas zoom.

Do not use:

```text
EPUB
 -> huge page
 -> InteractiveViewer
 -> user pans around
```

Instead:

```text
EPUB
  |
  v
Current reading position
  |
  v
Increase font/layout scale
  |
  v
Recalculate pagination
  |
  v
Restore reading position
  |
  v
Display new viewport-sized page
```

Example:

```text
Font size: 16
Pages: 280

       zoom in

Font size: 18
Pages: 315

       zoom in

Font size: 21
Pages: 370
```

The page itself never becomes larger than the available viewport.

---

# 10. Preserve Reading Position

When EPUB settings change, the reader must not lose their place.

Before reflow:

```text
Current location
Chapter 5
Paragraph 14
Text position
```

Save an EPUB-compatible locator.

Then:

```text
Change font size
        |
        v
Reflow EPUB
        |
        v
Recalculate pages
        |
        v
Find saved location
        |
        v
Display the same content
```

The user should feel like they simply changed reading size without being thrown to another part of the book.

This should also happen after:

- Font-size changes
- Margin changes
- Line-height changes
- Orientation changes
- Reader-width changes

---

# 11. EPUB Reader Settings

Create:

```dart
EpubReaderSettings(
  fontSize: 18,
  lineHeight: 1.5,
  margin: 20,
)
```

Possible future settings:

```dart
EpubReaderSettings(
  fontSize: 18,
  lineHeight: 1.5,
  margin: 20,
  theme: EpubTheme.light,
  readingMode: EpubReadingMode.paginated,
)
```

---

# 12. EPUB Reading Modes

Support the book-reader model first:

```dart
EpubReadingMode.paginated
```

Potential future mode:

```dart
EpubReadingMode.scrolled
```

### Paginated

```text
+-------------+
|             |
|   Chapter   |
|             |
|    text     |
|             |
+-------------+

        ->
```

Uses PaperFlip's page-curl engine.

### Scrolled

```text
+-------------+
|   Chapter   |
|             |
|    text     |
|             |
|    text     |
|             |
|    text     |
|             |
+-------------+
        |
        v
      scroll
```

Do not implement scrolling mode before the paginated mode is stable.

---

# 13. EPUB Internal Architecture

Suggested structure:

```text
lib/
  src/
    core/
      flip_book_widget.dart
      flip_book_controller.dart
      page_flip_painter.dart
      flip_settings.dart

    pdf/
      pdf_source.dart
      pdf_renderer.dart

    epub/
      epub_source.dart
      epub_document.dart
      epub_renderer.dart
      epub_pagination.dart
      epub_controller.dart
      epub_reader_settings.dart
```

---

# 14. EPUB Responsibilities

## `EpubDocument`

Responsible for:

- Opening EPUB
- Reading metadata
- Reading chapters
- Reading table of contents
- Resolving resources
- Managing book structure

## `EpubRenderer`

Responsible for:

- HTML
- CSS
- Text
- Images
- Fonts
- EPUB resources

## `EpubPagination`

Responsible for:

- Available width
- Available height
- Font size
- Line height
- Margins
- Chapter boundaries
- Page boundaries

Output:

```text
EPUB content
    ->
page 1
page 2
page 3
page 4
...
```

---

# 15. Rendering Engine Decision

Before fully integrating EPUB into PaperFlip, prototype the EPUB engine separately.

Investigate:

1. Readium-based Flutter integration
2. EPUB.js/WebView approach
3. Other maintained Flutter EPUB engines

The engine should be evaluated primarily for:

- EPUB 2/3 compatibility
- HTML/CSS support
- Reflow
- Pagination
- Font scaling
- Reading-position restoration
- Images
- Fonts
- Chapter navigation
- Platform support
- Flutter integration complexity

Do not commit the PaperFlip API to a specific EPUB engine too early.

The EPUB engine should be an internal implementation detail.

---

# 16. Landscape and Portrait

EPUB pagination must depend on the actual page viewport.

Portrait:

```text
+-------------+
|             |
|    EPUB     |
|    PAGE     |
|             |
+-------------+
```

Landscape:

```text
+-------------+-------------+
|             |             |
|    PAGE     |    PAGE     |
|             |             |
+-------------+-------------+
```

When orientation changes:

```text
Orientation changes
        |
        v
Available viewport changes
        |
        v
EPUB reflows
        |
        v
New pagination
        |
        v
Restore reading position
```

The existing PaperFlip page presentation logic should remain responsible for displaying the pages.

---

# 17. PDF Behavior

Do not redesign PDF around EPUB.

PDF remains:

```text
PDF
 |
 v
pdfrx
 |
 v
Fixed page
 |
 v
PaperFlip
```

No EPUB-style:

- Font scaling
- Reflow
- Line-height controls
- Margin controls

PDF-specific zoom can be considered later as an independent feature if needed.

---

# 18. Developer Experience

Default usage should be extremely simple.

### PDF

```dart
FlipBook.pdf(
  source: PdfSource.file(file),
)
```

### EPUB

```dart
FlipBook.epub(
  source: EpubSource.file(book),
)
```

The defaults should provide a usable reader without configuration.

Advanced developers can configure:

```dart
FlipBook.epub(
  source: EpubSource.file(book),
  controller: epubController,
  flip: FlipSettings(
    enabled: true,
    duration: Duration(milliseconds: 450),
  ),
  reader: EpubReaderSettings(
    fontSize: 18,
    margin: 20,
    lineHeight: 1.5,
  ),
)
```

---

# 19. Important Design Principle

PaperFlip should think in terms of:

```text
document -> viewport-sized page -> page flip
```

Not:

```text
document -> giant page -> zoom/pan
```

A "page" inside PaperFlip should represent:

> A piece of document content that fits the current reader viewport.

This allows the same page-flip engine to work with:

- PDF
- EPUB
- Images
- Custom Flutter widgets
- Future document formats

---

# 20. Development Roadmap

## Phase 1 — Stabilize Core

- Review current `FlipBookWidget`
- Review `FlipBookController`
- Review `PageFlipPainter`
- Extract common flip configuration
- Add `FlipSettings`
- Ensure page animation can be enabled/disabled
- Expose animation duration/curve
- Keep existing PDF behavior working

### Result

A stable generic page-flip engine.

---

## Phase 2 — Clean Public API

Implement:

```dart
FlipBook.pdf()
FlipBook.custom()
```

while keeping compatibility where practical.

Ensure document-specific implementations remain separate from the core.

---

## Phase 3 — EPUB Prototype

Before integrating with the flip engine:

- Open EPUB
- Parse metadata
- Parse chapters
- Read TOC
- Render HTML/CSS
- Display one viewport
- Test images
- Test fonts
- Test different EPUB structures

---

## Phase 4 — EPUB Pagination

Implement:

```text
viewport size
font size
line height
margin
        |
        v
pagination
        |
        v
pages
```

Test:

- Short chapters
- Long chapters
- Images
- Headings
- Lists
- Quotes
- Links
- Tables
- Different fonts

---

## Phase 5 — EPUB Reflow / Zoom

Implement:

```dart
epubController.zoomIn();
epubController.zoomOut();
epubController.setFontSize();
```

Behavior:

```text
Change reading size
       |
       v
Reflow
       |
       v
Repaginate
       |
       v
Restore reading position
```

This is the main differentiating feature.

---

## Phase 6 — Connect EPUB to PaperFlip

Feed the generated EPUB pages into the existing generic page builder:

```text
EPUB
 |
 v
EPUB Renderer
 |
 v
Pagination
 |
 v
Page Widgets
 |
 v
FlipBookWidget
 |
 v
PageFlipPainter
```

Do not duplicate the page-flip implementation.

---

## Phase 7 — Navigation

Add:

- Next/previous chapter
- TOC navigation
- Page navigation
- Reading progress
- Current location
- Restore last reading position

---

## Phase 8 — Orientation

Test:

- Portrait
- Landscape
- Rotation during reading
- Double-page landscape mode
- Reflow after rotation
- Reading-position restoration

---

## Phase 9 — Reader Customization

Add:

- Font size
- Line height
- Margins
- Light theme
- Dark theme
- Sepia/theme options
- Reading mode

Only add settings that can be implemented reliably across EPUB content.

---

## Phase 10 — Documentation

Update README with:

### Quick Start

```dart
FlipBook.epub(
  source: EpubSource.file(book),
)
```

### PDF

```dart
FlipBook.pdf(
  source: PdfSource.file(file),
)
```

### Custom Pages

```dart
FlipBook.custom(...)
```

### Flip Configuration

Explain:

- Animation enable/disable
- Duration
- Curve
- Direction
- Shadows
- Back face

### EPUB Reader

Explain:

- Reflow
- Font scaling
- Pagination
- Reading position
- Themes
- Chapter navigation

### Controller

Document all public controller methods.

---

# 21. Testing Strategy

## PDF

Verify existing functionality remains unchanged:

- Page rendering
- Page navigation
- Page curl
- Portrait
- Landscape
- Existing controller behavior

## EPUB

Test:

- EPUB 2
- EPUB 3
- Different chapter structures
- Images
- Fonts
- CSS
- Long books
- Large books
- Small screens
- Large screens

## Reflow

Test:

```text
16px -> 18px -> 22px -> 16px
```

Ensure the user stays at approximately the same reading location.

## Orientation

Test:

```text
Portrait -> Landscape -> Portrait
```

Ensure reading position is preserved.

## Flip

Test:

```text
enabled = true
enabled = false
duration changes
```

Ensure disabling the animation does not break navigation.

---

# 22. Performance Goals

Avoid rendering the entire EPUB into memory.

Use:

- Lazy page generation
- Lazy chapter loading
- Page caching
- Image caching where appropriate
- Limited active page widgets
- Background/precomputed pagination where possible

The page-flip animation should only require the current/nearby pages.

Target architecture:

```text
Book
 |
 +-- Chapter 1
 +-- Chapter 2
 +-- Chapter 3
       |
       v
Current page
Previous page
Next page
       |
       v
small active cache
```

---

# 23. Future Possibilities

Do not implement these immediately, but keep the architecture open for:

- Bookmarks
- Highlights
- Text selection
- Annotations
- Search
- Dictionary lookup
- Text-to-speech
- DRM-compatible sources
- CBZ/comic support
- HTML documents
- Image books
- Custom page transition effects
- Vertical reading
- RTL books
- CJK layout support

---

# 24. Final Product Vision

PaperFlip should eventually feel like:

```text
                  PAPERFLIP
                     |
       +-------------+-------------+
       |             |             |
      EPUB          PDF          Custom
       |             |             |
       +-------------+-------------+
                     |
              Common Flip Engine
                     |
       +-------------+-------------+
       |             |             |
     Curl         Animation      Navigation
       |             |             |
       +-------------+-------------+
                     |
              Flutter Widget
```

The developer gets a simple API:

```dart
FlipBook.epub(...)
```

or:

```dart
FlipBook.pdf(...)
```

while advanced developers can control:

```text
Flip animation
Animation duration
Animation curve
Animation enabled/disabled
Page navigation
EPUB font size
EPUB line height
EPUB margins
EPUB theme
Reading mode
Reading position
Chapter navigation
```

The central rule remains:

> **EPUB zoom is reflow, not page scaling.**

PDF remains fixed-layout.

The page-flip engine remains shared.

This keeps the implementation clean, makes the API easy to understand, and gives PaperFlip a path toward being a general-purpose Flutter book/document reader rather than only a PDF page-flip package.
