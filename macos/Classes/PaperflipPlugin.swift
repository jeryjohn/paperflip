import Cocoa
import FlutterMacOS

/// macOS registration for Paperflip's Dart-based renderer.
///
/// This platform currently has no native volume-key listener. The package's
/// widgets and PDF rendering use the shared Flutter/Dart implementations.
public class PaperflipPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    // Intentionally no native channels are registered on macOS.
  }
}
