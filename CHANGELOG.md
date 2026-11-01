# Changelog

All notable changes to Paperflip are documented here.

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.1] - 2026-11-01

### Added

- iOS and macOS platform support for the Paperflip reader and shared page-flip engine.
- Best-effort iOS volume-change observation through AVAudioSession output-volume KVO, with documented limitations.
- Updated example controls that expose volume-button navigation only on Android.

### Changed

- Improved native iOS observer lifecycle handling.
- Improved platform-specific documentation.
- Expanded volume-navigation API documentation.
- Updated example application platform behavior.
- Improved cross-platform CI validation.

### Fixed

- Fixed potentially disruptive `AVAudioSession.setActive(true)` and `setActive(false)` calls in the iOS plugin, preserving host application audio session lifecycle without unexpected deactivations.
- Removed unconditional production `NSLog` logging in the iOS plugin to prevent polluting consumer application logs.
- Fixed deterministic 32-bit integer multiplication in EPUB network cache key generation for web runtimes.

## [0.1.0] - 2026-10-25

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
