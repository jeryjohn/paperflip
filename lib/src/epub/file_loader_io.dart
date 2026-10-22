import 'dart:io' show File;
import 'dart:typed_data';

import 'package:paperflip/src/epub/epub_source.dart';

/// Reads raw EPUB bytes from the local filesystem on platforms supporting `dart:io`.
Future<Uint8List> loadFileBytes(String path) async {
  final file = File(path);
  if (!file.existsSync()) {
    throw EpubLoadException('No such file: $path');
  }
  return file.readAsBytes();
}
