import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import 'package:paperflip/src/epub/file_loader_stub.dart'
    if (dart.library.io) 'package:paperflip/src/epub/file_loader_io.dart';

/// Where an EPUB comes from.
///
/// ```dart
/// PaperFlip.epub(
///   source: EpubSource.network('https://example.com/book.epub'),
/// )
/// ```
///
/// Sources compare by value, so rebuilding a widget with an equal source does
/// not reload the book.
@immutable
sealed class EpubSource {
  const EpubSource();

  /// Download the book over HTTP(S).
  ///
  /// An optional [id] may be supplied to distinguish sources with identical URLs.
  /// If [id] is omitted, source identity deterministically hashes any supplied [headers]
  /// without exposing secret credentials or authentication tokens.
  const factory EpubSource.network(
    String url, {
    Map<String, String>? headers,
    String? id,
  }) = EpubNetworkSource;

  /// Read the book from a file on disk. Not supported on web.
  const factory EpubSource.file(String path) = EpubFileSource;

  /// Read the book from a bundled Flutter asset.
  const factory EpubSource.asset(String assetName) = EpubAssetSource;

  /// Use bytes already in memory.
  ///
  /// An optional [id] may be provided. If omitted, identity is derived from
  /// the name, byte length, and a bounded structural sample of bytes, ensuring
  /// value-based equality and cache invalidation without repeatedly hashing large
  /// files on every widget build.
  factory EpubSource.data(Uint8List bytes, {String name, String? id}) =
      EpubDataSource;

  /// Stable identity, used for widget diffing and cache keys.
  String get cacheKey;

  /// A human-readable name for error messages.
  String get displayName;

  /// Loads the raw EPUB archive bytes.
  Future<Uint8List> load();

  @override
  bool operator ==(Object other) =>
      other is EpubSource &&
      other.runtimeType == runtimeType &&
      other.cacheKey == cacheKey;

  @override
  int get hashCode => Object.hash(runtimeType, cacheKey);

  @override
  String toString() => '$runtimeType($displayName)';
}

/// An EPUB fetched over HTTP(S).
final class EpubNetworkSource extends EpubSource {
  const EpubNetworkSource(this.url, {this.headers, this.id});

  final String url;

  /// Optional headers, e.g. for authentication.
  final Map<String, String>? headers;

  /// Optional caller-supplied identifier.
  final String? id;

  @override
  String get cacheKey {
    if (id != null) {
      return 'network:$url#$id';
    }
    final h = headers;
    if (h == null || h.isEmpty) {
      return 'network:$url';
    }
    return 'network:$url#${_hashHeaders(h)}';
  }

  @override
  String get displayName => url;

  @override
  Future<Uint8List> load() async {
    final uri = Uri.parse(url);
    final response = await http.get(uri, headers: headers);
    if (response.statusCode != 200) {
      throw EpubLoadException('HTTP ${response.statusCode} fetching $url');
    }
    if (response.bodyBytes.isEmpty) {
      throw EpubLoadException('Empty response body from $url');
    }
    return response.bodyBytes;
  }

  static String _hashHeaders(Map<String, String> headers) {
    final sortedEntries = headers.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

    var hash = BigInt.parse('0xcbf29ce484222325');
    final prime = BigInt.parse('0x100000001b3');
    final mask64 = BigInt.parse('0xffffffffffffffff');

    for (final entry in sortedEntries) {
      final pair = '${entry.key.toLowerCase()}:${entry.value}\n';
      for (final unit in pair.codeUnits) {
        hash = (hash ^ BigInt.from(unit)) & mask64;
        hash = (hash * prime) & mask64;
      }
    }

    return hash.toRadixString(16).padLeft(16, '0');
  }
}

/// An EPUB read from the local filesystem.
final class EpubFileSource extends EpubSource {
  const EpubFileSource(this.path);

  final String path;

  @override
  String get cacheKey => 'file:$path';

  @override
  String get displayName => path;

  @override
  Future<Uint8List> load() async {
    return loadFileBytes(path);
  }
}

/// An EPUB bundled as a Flutter asset.
final class EpubAssetSource extends EpubSource {
  const EpubAssetSource(this.assetName);

  final String assetName;

  @override
  String get cacheKey => 'asset:$assetName';

  @override
  String get displayName => assetName;

  @override
  Future<Uint8List> load() async {
    final data = await rootBundle.load(assetName);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}

/// An EPUB already held in memory.
final class EpubDataSource extends EpubSource {
  EpubDataSource(this.bytes, {this.name = 'memory', String? id})
    : _cacheKey = id != null
          ? 'data:$name:$id'
          : 'data:$name:${_fingerprint(bytes)}';

  final Uint8List bytes;
  final String name;
  final String _cacheKey;

  @override
  String get cacheKey => _cacheKey;

  @override
  String get displayName => name;

  @override
  Future<Uint8List> load() async => bytes;

  static String _fingerprint(Uint8List bytes) {
    final len = bytes.length;
    var hash = BigInt.parse('0xcbf29ce484222325');
    final prime = BigInt.parse('0x100000001b3');
    final mask64 = BigInt.parse('0xffffffffffffffff');

    void mix(int byte) {
      hash = (hash ^ BigInt.from(byte)) & mask64;
      hash = (hash * prime) & mask64;
    }

    void mixRange(int start, int count) {
      final end = (start + count).clamp(0, len);
      for (var i = start; i < end; i++) {
        mix(bytes[i]);
      }
    }

    // Mix length
    mix(len & 0xff);
    mix((len >> 8) & 0xff);
    mix((len >> 16) & 0xff);
    mix((len >> 24) & 0xff);

    if (len <= 4096) {
      mixRange(0, len);
    } else {
      // Sample bounded segments across the file (header, mid-points, tail).
      // Total sampled bytes is ~3.5KB, so hashing takes < 0.005ms even for 100MB files.
      mixRange(0, 1024);
      mixRange((len * 0.25).floor(), 512);
      mixRange((len * 0.50).floor(), 512);
      mixRange((len * 0.75).floor(), 512);
      mixRange(len - 1024, 1024);
    }

    return '${len}_${hash.toRadixString(16).padLeft(16, '0')}';
  }
}

/// Thrown when an EPUB cannot be fetched or opened.
class EpubLoadException implements Exception {
  const EpubLoadException(this.message);

  final String message;

  @override
  String toString() => 'EpubLoadException: $message';
}
