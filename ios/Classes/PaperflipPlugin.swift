import AVFoundation
import Flutter
import UIKit

/// iOS implementation of Paperflip's optional volume-change listener.
///
/// iOS does not expose a public hardware volume-key-down event. This observes
/// AVAudioSession.outputVolume and infers direction from the change. It never
/// suppresses the system volume change or changes the audio-session category.
public class PaperflipPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let channelName = "io.github.jeryjohn.paperflip/volume_keys"

  private static var instance: PaperflipPlugin?
  private var channel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?
  private var volumeObservation: NSKeyValueObservation?
  private var previousVolume: Float?

  public static func register(with registrar: FlutterPluginRegistrar) {
    NSLog("[Paperflip iOS] registerWithRegistrar called")
    let instance = PaperflipPlugin()
    let channel = FlutterEventChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    instance.channel = channel
    channel.setStreamHandler(instance)
    self.instance = instance
    registrar.publish(instance)
    NSLog("[Paperflip iOS] plugin registered with event channel: %@", channelName)
  }

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    NSLog("[Paperflip iOS] onListen called")
    eventSink = events
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setActive(true)
      NSLog("[Paperflip iOS] AVAudioSession setActive(true) succeeded")
    } catch {
      NSLog("[Paperflip iOS] AVAudioSession setActive(true) failed: %@", error.localizedDescription)
    }
    previousVolume = session.outputVolume
    NSLog("[Paperflip iOS] observer setup for AVAudioSession.outputVolume, initial volume: %f", session.outputVolume)

    volumeObservation = session.observe(\.outputVolume, options: [.new]) {
      [weak self] _, change in
      let newVolume = change.newValue ?? AVAudioSession.sharedInstance().outputVolume
      DispatchQueue.main.async {
        guard let self = self else { return }
        guard let oldVolume = self.previousVolume else {
          self.previousVolume = newVolume
          return
        }
        self.previousVolume = newVolume
        NSLog("[Paperflip iOS] observed volume change: old=%f, new=%f", oldVolume, newVolume)
        let diff = newVolume - oldVolume
        guard abs(diff) > 0.0001 else { return }
        let direction = diff > 0 ? "up" : "down"
        NSLog("[Paperflip iOS] emitting volume event: %@", direction)
        self.eventSink?(direction)
      }
    }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    NSLog("[Paperflip iOS] onCancel called")
    volumeObservation?.invalidate()
    volumeObservation = nil
    previousVolume = nil
    eventSink = nil
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setActive(false, options: .notifyOthersOnDeactivation)
      NSLog("[Paperflip iOS] AVAudioSession setActive(false) succeeded")
    } catch {
      NSLog("[Paperflip iOS] AVAudioSession setActive(false) failed: %@", error.localizedDescription)
    }
    return nil
  }
}
