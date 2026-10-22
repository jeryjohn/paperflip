# Changelog

All notable changes to Paperflip are documented here.

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-10-23

### Added

- Initial public release of Paperflip.
- Mesh-based 3D page-curl engine with physical lighting, dynamic shadows, and drag-to-curl interaction.
- Reflowable EPUB reader with document parsing, HTML-based content rendering, pagination, reader settings (font sizing, themes, margins, line heights), and reading-position restoration.
- PDF page-flip integration built on `pdfrx`, with progressive rendering, bounded LRU caching, and safe image lifecycle management.
- Custom Flutter page-builder API (`PaperFlip.custom`) allowing arbitrary widget pages to use page-curl rendering.
- Hardware volume button navigation on supported Android devices (`VolumeKeyManager`).
- Full-screen `PaperFlipReader` with auto-hiding controls, page selector dialog, and lightweight fallback for constrained devices.
- Programmatic navigation via `PaperFlipController`.
- Complete example application demonstrating EPUB, PDF, and custom widget screens.
- Package documentation, unit and widget tests, and MIT license.

[Unreleased]: https://github.com/jeryjohn/paperflip/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/jeryjohn/paperflip/releases/tag/v0.1.0
