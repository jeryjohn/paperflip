import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperflip/src/memory/device_memory.dart';

void main() {
  group('DeviceMemory probe', () {
    test(
      'returns null gracefully on unsupported platforms without throwing',
      () async {
        final iosMemory = await getDeviceTotalMemoryMB(
          platform: TargetPlatform.iOS,
        );
        expect(iosMemory, isNull);

        final macosMemory = await getDeviceTotalMemoryMB(
          platform: TargetPlatform.macOS,
        );
        expect(macosMemory, isNull);

        final windowsMemory = await getDeviceTotalMemoryMB(
          platform: TargetPlatform.windows,
        );
        expect(windowsMemory, isNull);
      },
    );

    test(
      'android probe returns null safely when /proc/meminfo does not exist or fails',
      () async {
        final androidMemory = await getDeviceTotalMemoryMB(
          platform: TargetPlatform.android,
        );
        // In host test environment (macOS), /proc/meminfo either doesn't exist or is not Android
        // Must not throw exception
        expect(androidMemory == null || androidMemory > 0, isTrue);
      },
    );
  });
}
