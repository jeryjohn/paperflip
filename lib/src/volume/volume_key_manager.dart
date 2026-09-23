import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Client interface for widgets receiving hardware volume-key navigation events.
abstract interface class VolumeKeyClient {
  /// Invoked when Volume Up is pressed (Next Page).
  void onVolumeUp();

  /// Invoked when Volume Down is pressed (Previous Page).
  void onVolumeDown();
}

/// Shared manager that coordinates Android hardware volume-key events across
/// active readers.
///
/// Hardware volume keys are only intercepted on Android when at least one
/// reader has opted in via `useVolumeKeys: true`. When no active reader is
/// listening, or on non-Android platforms, no platform channel listener is
/// active and Android system volume remains unaffected.
///
/// When multiple readers exist in the widget tree or navigation stack,
/// events are deterministically routed to the topmost (most recently registered)
/// active client.
class VolumeKeyManager {
  VolumeKeyManager._();

  /// The singleton instance of [VolumeKeyManager].
  static final VolumeKeyManager instance = VolumeKeyManager._();

  static const EventChannel _channel =
      EventChannel('io.github.jeryjohn.paperflip/volume_keys');

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
  VolumeKeyClient? get activeClient =>
      _clients.isEmpty ? null : _clients.last;

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
  /// If no clients remain, the underlying platform channel stream is canceled,
  /// causing Android native code to restore default system volume handling.
  void unregisterClient(VolumeKeyClient client) {
    _clients.remove(client);
    _syncSubscription();
  }

  void _syncSubscription() {
    final platform = debugPlatformOverride ?? defaultTargetPlatform;
    final shouldListen =
        _clients.isNotEmpty && platform == TargetPlatform.android;

    if (shouldListen && _subscription == null) {
      _subscription = _channel.receiveBroadcastStream().listen(
        _handleEvent,
        onError: (Object error) {
          // Swallow or handle stream errors safely
        },
      );
    } else if (!shouldListen && _subscription != null) {
      _subscription?.cancel();
      _subscription = null;
    }
  }

  void _handleEvent(dynamic event) {
    if (_clients.isEmpty) return;
    final active = _clients.last;
    if (event == 'up') {
      active.onVolumeUp();
    } else if (event == 'down') {
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

