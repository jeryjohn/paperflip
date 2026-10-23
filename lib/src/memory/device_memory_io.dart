import 'dart:io';

import 'package:flutter/foundation.dart';

/// Reads `/proc/meminfo` on Android devices to detect total system RAM.
Future<int?> getDeviceTotalMemoryMB({TargetPlatform? platform}) async {
  if (kIsWeb) return null;
  final effectivePlatform = platform ?? defaultTargetPlatform;
  if (effectivePlatform != TargetPlatform.android) return null;

  try {
    final file = File('/proc/meminfo');
    if (!await file.exists()) return null;
    final memInfo = await file.readAsString();
    final match = RegExp(r'MemTotal:\s+(\d+)\s+kB').firstMatch(memInfo);
    if (match != null) {
      final totalMemKB = int.parse(match.group(1)!);
      return totalMemKB ~/ 1024;
    }
  } catch (_) {
    // Probing failed safely.
  }
  return null;
}
