import 'dart:typed_data';

import 'package:paperflip/src/epub/epub_source.dart';

/// Web fallback for [EpubFileSource], which is unsupported on web.
Future<Uint8List> loadFileBytes(String path) async {
  throw const EpubLoadException(
    'EpubSource.file is not supported on web; use .network, .asset, or .data.',
  );
}
