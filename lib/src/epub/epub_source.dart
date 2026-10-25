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
  factory EpubSource.network(
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
  /// Takes a defensive snapshot of [bytes] so that external mutations to the
  /// input array cannot alter this source's content or cause silent identity drift.
  ///
  /// An optional [id] may be provided. If omitted, identity is derived from
  /// the name, byte length, and an efficient 64-bit content digest.
  ///
  /// Callers should create an [EpubSource] instance once (e.g. in `initState`
  /// or a view model) and reuse it across builds rather than re-instantiating it
  /// on every frame, avoiding repeated memory snapshots and hashing during rebuilds.
  /// Supplying an explicit [id] avoids content-hashing overhead, while a defensive
  /// copy still takes time proportional to the input size.
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
  EpubNetworkSource(this.url, {Map<String, String>? headers, this.id})
    : headers = headers == null
          ? null
          : Map.unmodifiable(Map<String, String>.from(headers)),
      _cacheKey = _buildCacheKey(
        url,
        id,
        headers == null ? null : Map<String, String>.from(headers),
      );

  final String url;

  /// Optional headers, e.g. for authentication. Stored as an unmodifiable copy.
  final Map<String, String>? headers;

  /// Optional caller-supplied identifier.
  final String? id;

  final String _cacheKey;

  @override
  String get cacheKey => _cacheKey;

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

  static String _buildCacheKey(
    String url,
    String? id,
    Map<String, String>? headers,
  ) {
    if (id != null) {
      return 'network:$url#$id';
    }
    if (headers == null || headers.isEmpty) {
      return 'network:$url';
    }
    return 'network:$url#${_hashHeaders(headers)}';
  }

  static String _hashHeaders(Map<String, String> headers) {
    final sortedEntries = headers.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

    var h1 = 0x811c9dc5;
    var h2 = 0x84222325;
    const p1 = 16777619;
    const p2 = 0x01000193;

    for (final entry in sortedEntries) {
      final pair = '${entry.key.toLowerCase()}:${entry.value}\n';
      for (final unit in pair.codeUnits) {
        h1 = _mul32(h1 ^ unit, p1);
        h2 = _mul32(h2 ^ (unit + 7), p2);
      }
    }

    return '${h1.toRadixString(16).padLeft(8, '0')}${h2.toRadixString(16).padLeft(8, '0')}';
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
  /// Creates an in-memory EPUB source from [bytes].
  ///
  /// Takes a defensive snapshot of [bytes] so that external mutations to the
  /// input array cannot alter this source's content or cause silent identity drift.
  ///
  /// An optional [id] may be provided. If omitted, identity is derived from
  /// the name, byte length, and an efficient 64-bit content digest.
  ///
  /// Callers should create an [EpubSource] instance once (e.g. in `initState`
  /// or a view model) and reuse it across builds rather than re-instantiating it
  /// on every frame, avoiding repeated memory snapshots and hashing during rebuilds.
  /// Supplying an explicit [id] avoids content-hashing overhead, while a defensive
  /// copy still takes time proportional to the input size.
  EpubDataSource(Uint8List bytes, {this.name = 'memory', String? id})
    : _bytes = Uint8List.fromList(bytes),
      _cacheKey = id != null
          ? 'data:$name:$id'
          : 'data:$name:${_computeDigest(bytes)}';

  final Uint8List _bytes;
  final String name;
  final String _cacheKey;

  /// Returns a defensive copy of the stored archive bytes.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  @override
  String get cacheKey => _cacheKey;

  @override
  String get displayName => name;

  @override
  Future<Uint8List> load() async => Uint8List.fromList(_bytes);

  static String _computeDigest(Uint8List bytes) {
    final len = bytes.length;
    var h1 = 0x811c9dc5;
    var h2 = 0x84222325;
    const p1 = 16777619;
    const p2 = 0x01000193;

    // Mix length
    h1 = _mul32(h1 ^ len, p1);
    h2 = _mul32(h2 ^ (len >> 8), p2);

    for (var i = 0; i < len; i++) {
      final b = bytes[i];
      h1 = _mul32(h1 ^ b, p1);
      h2 = _mul32(h2 ^ (b + (i & 0xFF)), p2);
    }

    return '${len}_${h1.toRadixString(16).padLeft(8, '0')}${h2.toRadixString(16).padLeft(8, '0')}';
  }
}

/// Multiplies two 32-bit unsigned integers modulo 2^32 deterministically across
/// native Dart (64-bit int) and Flutter Web (JavaScript IEEE-754 numbers).
///
/// Splitting operands into 16-bit halves ensures all intermediate products
/// stay well within 32 bits, avoiding JavaScript's 53-bit precision boundary
/// where 64-bit multiplication truncates low-order bits on web runtimes.
int _mul32(int a, int b) {
  final ua = a.toUnsigned(32);
  final ub = b.toUnsigned(32);
  final aLow = ua & 0xffff;
  final aHigh = (ua >> 16) & 0xffff;
  final bLow = ub & 0xffff;
  final bHigh = (ub >> 16) & 0xffff;

  final low = aLow * bLow;
  final mid = (aLow * bHigh + aHigh * bLow) & 0xffff;
  return (low + (mid * 65536)).toUnsigned(32);
}

/// Thrown when an EPUB cannot be fetched or opened.
class EpubLoadException implements Exception {
  const EpubLoadException(this.message);

  final String message;

  @override
  String toString() => 'EpubLoadException: $message';
}
