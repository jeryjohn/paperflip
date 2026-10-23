import 'package:flutter/foundation.dart';

/// Fallback stub for platforms without dart:io (such as web).
Future<int?> getDeviceTotalMemoryMB({TargetPlatform? platform}) async => null;
