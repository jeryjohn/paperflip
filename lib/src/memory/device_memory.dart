import 'package:flutter/foundation.dart';
import 'package:paperflip/src/memory/device_memory_stub.dart'
    if (dart.library.io) 'package:paperflip/src/memory/device_memory_io.dart'
    as impl;

/// Probes device total RAM in megabytes on supported native platforms (Android),
/// returning `null` on unsupported platforms (web, iOS, desktop without /proc)
/// or when probing fails.
Future<int?> getDeviceTotalMemoryMB({TargetPlatform? platform}) =>
    impl.getDeviceTotalMemoryMB(platform: platform);
