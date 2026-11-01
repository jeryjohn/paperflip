import AVFoundation
import Flutter
import UIKit

/// iOS implementation of Paperflip's optional volume-change listener.
///
/// iOS does not expose a public hardware volume-key-down event. This observes
/// `AVAudioSession.sharedInstance().outputVolume` via KVO and infers direction
/// from the difference. It does not alter or take ownership of the host application's
/// audio-session category, mode, or active state, and leaves normal system volume
/// behavior intact.
public class PaperflipPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let channelName = "io.github.jeryjohn.paperflip/volume_keys"

  private var channel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?
  private var volumeObservation: NSKeyValueObservation?
  private var previousVolume: Float?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = PaperflipPlugin()
    let channel = FlutterEventChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    instance.channel = channel
    channel.setStreamHandler(instance)
    registrar.publish(instance)
  }

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events

    let session = AVAudioSession.sharedInstance()
    previousVolume = session.outputVolume

    volumeObservation?.invalidate()
    volumeObservation = session.observe(\.outputVolume, options: [.new]) {
      [weak self] _, change in
      let newVolume = change.newValue ?? AVAudioSession.sharedInstance().outputVolume
      DispatchQueue.main.async {
        guard let self = self, let sink = self.eventSink else { return }
        guard let oldVolume = self.previousVolume else {
          self.previousVolume = newVolume
          return
        }
        self.previousVolume = newVolume
        let diff = newVolume - oldVolume
        guard abs(diff) > 0.0001 else { return }
        let direction = diff > 0 ? "up" : "down"
        sink(direction)
      }
    }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stopObserving()
    return nil
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    channel?.setStreamHandler(nil)
    channel = nil
    stopObserving()
  }

  private func stopObserving() {
    volumeObservation?.invalidate()
    volumeObservation = nil
    previousVolume = nil
    eventSink = nil
  }

  deinit {
    stopObserving()
  }
}
