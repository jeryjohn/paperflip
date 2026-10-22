# Paperflip
[![pub package](https://img.shields.io/pub/v/paperflip.svg)](https://pub.dev/packages/paperflip)

[![pub points](https://img.shields.io/pub/points/paperflip)](https://pub.dev/packages/paperflip/score)

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**A mesh-based page-flip engine for Flutter.** Build book-like reading experiences with EPUB documents, PDF files, or your own Flutter page widgets.

> Paperflip is in its initial-release stage. The public API may evolve before version `1.0.0`.

## Features
- **One rendering engine:** EPUB, PDF, and custom page content share the `MeshPaperFlip` rendering pipeline.
- **3D page curl:** Mesh-based page deformation with perspective projection, lighting, and fold shadows.
- **EPUB reader:** Document loading, HTML-based content rendering, pagination, reading-position support, and reader settings.
- **PDF reader:** PDF document and page rendering through [`pdfrx`](https://pub.dev/packages/pdfrx).
- **Custom pages:** Supply Flutter widgets to create books, magazines, catalogs, tutorials, or other page-based interfaces.
- **Gesture interaction:** Drag pages to turn them, with animation settling handled by the renderer.
- **Controller support:** Use the package's controller APIs for supported programmatic navigation.
- **Texture lifecycle management:** Rendered page textures are managed internally for the mesh renderer.

Paperflip focuses on page rendering and navigation. Persistent/offline caching of original documents is an application-level decision; the package's rendered-texture cache is not a replacement for a download or storage layer.

## Installation
Add Paperflip to your Flutter project:

```bash
flutter pub add paperflip
```

Or add it manually to `pubspec.yaml`:

```yaml
dependencies:
  paperflip: ^0.1.0
```

Then fetch dependencies:

```bash
flutter pub get
```

Import the package:

```dart
import 'package:paperflip/paperflip.dart';
```

## Quick start: custom pages
Use `PaperFlip.custom` when you want full control over the content of each page.

```dart
import 'package:flutter/material.dart';
import 'package:paperflip/paperflip.dart';
class CustomBookScreen extends StatelessWidget {
  const CustomBookScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paperflip')),
      body: PaperFlip.custom(
        pageCount: 6,
        pageBuilder: (context, index, constraints) {
          return Container(
            color: index.isEven ? Colors.white : Colors.blueGrey.shade50,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(24),
            child: Text(
              'Page ${index + 1}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          );
        },
      ),
    );
  }
}
```

The builder receives the page index and the constraints for the page content. Build each page as a normal Flutter widget; Paperflip handles the page-curl rendering.

## EPUB
Paperflip provides an EPUB source abstraction and an EPUB reader that handles document loading, content rendering, pagination, and reading-position mapping.

### Asset Version
```dart
import 'package:flutter/material.dart';
import 'package:paperflip/paperflip.dart';
class EpubAssetScreen extends StatelessWidget {
  const EpubAssetScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PaperFlip.epub(
        source: EpubSource.asset('assets/books/sample.epub'),
      ),
    );
  }
}
```

Register the asset in your `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/books/sample.epub
```

### Online Link (Network URL) Version
```dart
import 'package:flutter/material.dart';
import 'package:paperflip/paperflip.dart';
class EpubNetworkScreen extends StatelessWidget {
  const EpubNetworkScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PaperFlip.epub(
        source: const EpubSource.network(
          'https://www.gutenberg.org/cache/epub/28885/pg28885-images.epub',
        ),
      ),
    );
  }
}
```

Other supported sources are `EpubSource.file(path)` (not supported on web) and `EpubSource.data(bytes, name: ...)`.

> **EPUB styling scope**: To composite pages seamlessly into the 3D page-curl mesh without platform view lag, Paperflip renders EPUB XHTML documents using pure Flutter widgets (`flutter_widget_from_html_core`). Configurable font sizes, line heights, fonts, themes, margins, headings, and inline HTML styles are supported. External CSS stylesheets are intentionally not evaluated.

## PDF
Paperflip uses `pdfrx` to open PDF documents and renders PDF pages through the shared mesh-based page-flip engine.

### Asset Version
```dart
import 'package:flutter/material.dart';
import 'package:paperflip/paperflip.dart';
class PdfAssetScreen extends StatelessWidget {
  const PdfAssetScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PaperFlip.pdf(
        source: PdfDocumentRefAsset('assets/books/sample.pdf'),
      ),
    );
  }
}
```

Register the PDF in your `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/books/sample.pdf
```

### Online Link (Network URL) Version
```dart
import 'package:flutter/material.dart';
import 'package:paperflip/paperflip.dart';
class PdfNetworkScreen extends StatelessWidget {
  const PdfNetworkScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PaperFlip.pdf(
        source: PdfDocumentRefUri(
          Uri.parse('https://examplefiles.org/files/documents/pdf-sample-50-pages.pdf'),
        ),
      ),
    );
  }
}
```

Other supported sources include `PdfDocumentRefFile(path)` and `PdfDocumentRefData(bytes, sourceName: ...)`.

## Controller
Control page navigation and curl animations programmatically:

```dart
final controller = PaperFlipController();
// Flip to next/previous page with animation
controller.flipNext();
controller.flipPrev();
// Jump directly or animate to a specific page
controller.goToPage(5);                 // animated
controller.goToPage(5, animate: false);  // instant jump
```

## Run the example app
The repository includes a complete example Flutter application showcasing EPUB, PDF, and custom widget screens:

- [Custom Screen](example/lib/features/custom/custom_screen.dart) — Interactive custom Flutter widgets with curl controls
- [EPUB Screen](example/lib/features/epub/epub_screen.dart) — Project Gutenberg reflowable EPUB with themes, font scaling, and TOC
- [PDF Screen](example/lib/features/pdf/pdf_screen.dart) — 50-page online PDF reader with page jumping and hardware volume keys

To run the example app locally:

```bash
cd example
flutter pub get
flutter run
```

## Architecture overview
Document formats prepare page content, while the mesh renderer handles the page turn:

```text
EPUB source ──> EPUB rendering + pagination ─┐
                                             │
PDF source  ──> PDF page widgets ────────────┼──> MeshPaperFlip
                                             │        │
Custom pageBuilder ──────────────────────────┘        v
                                              Page capture / textures
                                                       │
                                                       v
                                           Mesh geometry + perspective
                                                       │
                                                       v
                                              3D page-curl rendering
```

The rendering pipeline includes page texture capture and caching, front/back sheet handling, mesh geometry, camera projection, and canvas vertex rendering. EPUB and PDF remain responsible for preparing the underlying document content.

## Caching and memory
Paperflip manages the rendered page textures needed by its mesh renderer. Document parsing and PDF rendering also have their own lifecycles and behavior from the underlying format libraries.

- Treat original-file persistence and offline downloads as an application-level concern unless a future Paperflip API explicitly provides them.
- Dispose reader widgets/controllers according to their documented lifecycle.
- Test memory use with large documents and on the devices you intend to support.
- Avoid assuming that rendered textures are persistent disk caches.

Advanced cache tuning and prefetch controls may evolve in future releases.

## Dependencies
Paperflip builds on the Flutter widget/rendering system and uses supporting packages for document processing. Notable dependencies in the current implementation include:

- [`epub_plus`](https://pub.dev/packages/epub_plus) for EPUB parsing.
- [`flutter_widget_from_html_core`](https://pub.dev/packages/flutter_widget_from_html_core) for HTML-based EPUB content.
- [`pdfrx`](https://pub.dev/packages/pdfrx) for PDF document and page rendering.

The exact dependency versions are declared in `pubspec.yaml`.

## Platform support
Paperflip supports Android, iOS, macOS, Windows, Linux, and Web:
- **Android**: Full support, including optional hardware volume button page turns.
- **iOS, macOS, Windows, Linux**: Full support for custom widgets, EPUB, and PDF rendering.
- **Web**: Supported for custom widgets, PDF rendering, and network, asset, and in-memory EPUB sources (`EpubSource.file` is unsupported on web).

Always test your application on your target devices and operating system versions before shipping.

## Testing and analysis
Run these commands from the package root:

```bash
flutter analyze
flutter test
dart pub publish --dry-run
```

If the project uses [FVM](https://fvm.app/), run the corresponding commands with `fvm flutter` so the project-pinned SDK is used consistently.

## Contributing
Paperflip welcomes focused bug fixes, documentation improvements, tests, and well-scoped features. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

**All contributions must be submitted through pull requests. Direct pushes to `main` are not accepted.** Pull requests must pass the project's required checks and receive approval from the repository owner or an authorized maintainer before merging. Contributors cannot merge their own pull requests unless they are explicitly authorized maintainers and repository rules permit it.

For meaningful changes, open an issue first to discuss the approach. Keep pull requests focused, include tests for behavior changes, and update documentation when public behavior or APIs change.

## Reporting issues
Please include:

- Paperflip version and Flutter/Dart versions.
- Target platform and device/OS version.
- Whether the issue occurs with EPUB, PDF, or custom content.
- Minimal reproduction steps and relevant logs.
- A small, redistributable sample document when the issue depends on a file.

Report issues at [GitHub Issues](https://github.com/jeryjohn/paperflip/issues).

## Changelog
See [`CHANGELOG.md`](CHANGELOG.md) for release history and planned changes.

## License
Paperflip is distributed under the MIT License. See [`LICENSE`](LICENSE) for details.
