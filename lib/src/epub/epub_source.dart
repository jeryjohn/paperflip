import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

/// Where an EPUB comes from.
///
/// ```dart
/// FlipBook.epub(
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
  const factory EpubSource.network(String url, {Map<String, String>? headers}) =
      EpubNetworkSource;

  /// Read the book from a file on disk. Not supported on web.
  const factory EpubSource.file(String path) = EpubFileSource;

  /// Read the book from a bundled Flutter asset.
  const factory EpubSource.asset(String assetName) = EpubAssetSource;

  /// Use bytes already in memory.
  factory EpubSource.data(Uint8List bytes, {String name}) = EpubDataSource;

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
  const EpubNetworkSource(this.url, {this.headers});

  final String url;

  /// Optional headers, e.g. for authentication.
  final Map<String, String>? headers;

  @override
  String get cacheKey => 'network:$url';

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
    if (kIsWeb) {
      throw const EpubLoadException(
        'EpubSource.file is not supported on web; use .network or .asset.',
      );
    }
    final file = File(path);
    if (!file.existsSync()) {
      throw EpubLoadException('No such file: $path');
    }
    return file.readAsBytes();
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
  EpubDataSource(this.bytes, {this.name = 'memory'})
    : _identity = '$name:${bytes.length}:${bytes.hashCode}';

  final Uint8List bytes;
  final String name;
  final String _identity;

  @override
  String get cacheKey => 'data:$_identity';

  @override
  String get displayName => name;

  @override
  Future<Uint8List> load() async => bytes;
}

/// Thrown when an EPUB cannot be fetched or opened.
class EpubLoadException implements Exception {
  const EpubLoadException(this.message);

  final String message;

  @override
  String toString() => 'EpubLoadException: $message';
}
