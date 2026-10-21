# Changelog

All notable changes to Paperflip are documented here.

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Prepare the initial public release of Paperflip.
- Mesh-based page-curl rendering shared by EPUB, PDF, and custom page content.
- EPUB loading, HTML content rendering, pagination, reader settings, and reading-position support.
- PDF page-flip integration through `pdfrx`.
- Custom Flutter page-builder API.
- Page texture capture and caching, front/back sheet handling, mesh geometry, perspective projection, lighting, and shadows.
- Controller-driven page navigation and gesture-based page turns.
- Example Flutter application demonstrating EPUB, PDF, and Custom content.
- Release documentation and MIT license.

### Planned / follow-up

- Expand EPUB fixture coverage where test documents are available and redistributable.
- Profile memory use and refine cache tuning and prefetch controls in a later phase.

> When version `0.1.0` is published, move the released entries into a dated `0.1.0` section and update the comparison links below.

[Unreleased]: https://github.com/jeryjohn/paperflip/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/jeryjohn/paperflip/releases/tag/v0.1.0
