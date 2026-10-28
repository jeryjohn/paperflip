import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Web registration shim for the Dart-based Paperflip widgets.
///
/// Browser applications don't expose reliable physical volume-key events, so
/// this plugin intentionally registers no volume-key channel.
class PaperflipWebPlugin {
  static void registerWith(Registrar registrar) {
    // The renderer itself is platform-neutral Dart/Flutter code.
  }
}
