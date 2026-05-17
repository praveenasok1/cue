import AVFoundation
import Flutter
import flutter_foreground_task
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterStreamHandler {
  private let routeChannelName = "cue/audio_route"
  private let routeEventsChannelName = "cue/audio_route_events"
  private var routeEventSink: FlutterEventSink?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    SwiftFlutterForegroundTaskPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    prepareAudioSession()
    guard let messenger = audioRouteBinaryMessenger() else {
      NSLog("CUE: failed to attach audio route channels")
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    FlutterMethodChannel(
      name: routeChannelName,
      binaryMessenger: messenger
    ).setMethodCallHandler { [weak self] call, result in
      guard call.method == "currentRoute" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.currentRouteState() ?? ["earphonesConnected": false, "routeName": "None"])
    }

    FlutterEventChannel(
      name: routeEventsChannelName,
      binaryMessenger: messenger
    ).setStreamHandler(self)

    // Listen for audio route changes (covers wired + Bluetooth + AirPods removal).
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleRouteChange(_:)),
      name: AVAudioSession.routeChangeNotification,
      object: nil
    )
    // Re-check when app comes to foreground – AirPods state may have changed while suspended.
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appBecameActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - FlutterStreamHandler

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    routeEventSink = events
    events(currentRouteState())
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    routeEventSink = nil
    return nil
  }

  // MARK: - Route-change observer (in-ear detection)

  @objc private func handleRouteChange(_ notification: Notification) {
    guard let info = notification.userInfo,
          let reasonRaw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else {
      emitRouteState()
      return
    }

    switch reason {
    case .oldDeviceUnavailable:
      // Earphone physically removed or AirPods taken out of ear –
      // send immediately so Dart stops recording without delay.
      DispatchQueue.main.async { [weak self] in
        self?.routeEventSink?(["earphonesConnected": false, "routeName": "Device speaker"])
      }
    case .newDeviceAvailable:
      // Earphone plugged in or AirPods placed in ear.
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.routeEventSink?(self.currentRouteState())
      }
    default:
      emitRouteState()
    }
  }

  @objc private func appBecameActive() {
    emitRouteState()
  }

  private func emitRouteState() {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.routeEventSink?(self.currentRouteState())
    }
  }

  // MARK: - Route state

  private func currentRouteState() -> [String: Any] {
    let session = AVAudioSession.sharedInstance()
    // Check active outputs first (what audio is going to).
    let output = session.currentRoute.outputs.first(where: isEarphonePort)
    // Fall back to checking available inputs (AirPods mic present but not actively routing).
    let input = session.availableInputs?.first(where: isEarphonePort)
    let name = output?.portName ?? input?.portName ?? "Device speaker"
    return [
      "earphonesConnected": output != nil || input != nil,
      "routeName": name,
    ]
  }

  private func isEarphonePort(_ p: AVAudioSessionPortDescription) -> Bool {
    switch p.portType {
    case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .headphones, .headsetMic, .usbAudio:
      return true
    default:
      return false
    }
  }

  // MARK: - Audio session setup

  private func prepareAudioSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      // .playAndRecord + .spokenAudio ensures iOS uses the correct mic path
      // for earphones. .allowBluetooth enables HFP (call quality) for AirPods.
      // Do NOT call setActive(true) here – the Dart record/audio_session
      // packages manage activation themselves at recording time.
      try session.setCategory(
        .playAndRecord,
        mode: .spokenAudio,
        options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
      )
    } catch {
      NSLog("CUE: AVAudioSession category error: \(error)")
    }
  }

  // MARK: - Messenger helper

  private func audioRouteBinaryMessenger() -> FlutterBinaryMessenger? {
    if let vc = window?.rootViewController as? FlutterViewController {
      return vc.binaryMessenger
    }
    return registrar(forPlugin: "AudioSessionPlugin")?.messenger()
  }
}
