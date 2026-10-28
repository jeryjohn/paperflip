import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Client interface for widgets receiving hardware volume-key navigation events.
abstract interface class VolumeKeyClient {
  /// Invoked when Volume Up is pressed or an upward volume change is observed.
  void onVolumeUp();

  /// Invoked when Volume Down is pressed or a downward volume change is observed.
  void onVolumeDown();
}

/// Shared manager that coordinates volume-key navigation across active readers.
///
/// Android intercepts hardware volume key events while an opted-in reader is
/// active. On iOS, the native plugin observes changes to AVAudioSession's
/// system output volume and infers the direction; it does not intercept the
/// key-down event or suppress normal system volume behavior. On iOS, changes
/// from Control Center or connected devices can also be observed, and there is
/// no change event when the volume is already at a limit. Other platforms do
/// not provide volume-key navigation through this manager.
///
/// When multiple readers exist in the widget tree or navigation stack, events
/// are routed to the topmost (most recently registered) active client.
class VolumeKeyManager {
  VolumeKeyManager._();

  /// The singleton instance of [VolumeKeyManager].
  static final VolumeKeyManager instance = VolumeKeyManager._();

  static const EventChannel _channel = EventChannel(
    'io.github.jeryjohn.paperflip/volume_keys',
  );

  final List<VolumeKeyClient> _clients = [];
  StreamSubscription<dynamic>? _subscription;

  /// Optional platform override for testing.
  @visibleForTesting
  static TargetPlatform? debugPlatformOverride;

  /// Whether the platform event stream is currently actively subscribed.
  bool get isListening => _subscription != null;

  /// The number of registered clients.
  int get clientCount => _clients.length;

  /// The currently active client receiving volume key events, or `null`.
  VolumeKeyClient? get activeClient => _clients.isEmpty ? null : _clients.last;

  /// Registers [client] to receive volume key events.
  ///
  /// If the client was already registered, it is promoted to the top of the
  /// active stack.
  void registerClient(VolumeKeyClient client) {
    _clients.remove(client);
    _clients.add(client);
    _syncSubscription();
  }

  /// Unregisters [client] from receiving volume key events.
  ///
  /// If no clients remain, the platform stream is canceled and native
  /// observation/interception is stopped.
  void unregisterClient(VolumeKeyClient client) {
    _clients.remove(client);
    _syncSubscription();
  }

  void _syncSubscription() {
    final platform = debugPlatformOverride ?? defaultTargetPlatform;
    final supportsVolumeEvents =
        !kIsWeb &&
        (platform == TargetPlatform.android || platform == TargetPlatform.iOS);
    final shouldListen = _clients.isNotEmpty && supportsVolumeEvents;

    if (shouldListen && _subscription == null) {
      debugPrint(
        '[Paperflip Dart] VolumeKeyManager: subscribing to EventChannel',
      );
      _subscription = _channel.receiveBroadcastStream().listen(
        _handleEvent,
        onError: (Object error) {
          // Channel setup may fail on a host app that has not registered the
          // plugin correctly. The reader should remain usable without keys.
          debugPrint(
            '[Paperflip Dart] Paperflip volume-key stream failed: $error',
          );
        },
      );
    } else if (!shouldListen && _subscription != null) {
      debugPrint('[Paperflip Dart] VolumeKeyManager: canceling subscription');
      _subscription?.cancel();
      _subscription = null;
    }
  }

  void _handleEvent(dynamic event) {
    debugPrint('[Paperflip Dart] VolumeKeyManager received event: $event');
    if (_clients.isEmpty) {
      debugPrint(
        '[Paperflip Dart] VolumeKeyManager: no active clients to receive event',
      );
      return;
    }
    final active = _clients.last;
    if (event == 'up') {
      debugPrint('[Paperflip Dart] dispatching onVolumeUp to active client');
      active.onVolumeUp();
    } else if (event == 'down') {
      debugPrint('[Paperflip Dart] dispatching onVolumeDown to active client');
      active.onVolumeDown();
    }
  }

  /// Manually dispatches an event string ('up' or 'down') to the active client.
  ///
  /// Useful for automated testing without platform channels.
  @visibleForTesting
  void handleEventForTesting(String event) {
    _handleEvent(event);
  }

  /// Resets client registrations, platform override, and subscription state.
  ///
  /// Intended for test teardown.
  @visibleForTesting
  void resetForTesting() {
    _subscription?.cancel();
    _subscription = null;
    _clients.clear();
    debugPlatformOverride = null;
  }
}
