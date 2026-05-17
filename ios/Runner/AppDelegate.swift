import AVFoundation
import Flutter
import flutter_foreground_task
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterStreamHandler {
  private let routeChannelName = "cue/audio_route"
  private let routeEventsChannelName = "cue/audio_route_events"
  private var routeEventSink: FlutterEventSink?
  private var routeChannelsAttached = false

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

    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    attachAudioRouteChannelsWhenReady()
    return launched
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
        self?.routeEventSink?(self?.fallbackRouteState() ?? [
          "earphonesConnected": false,
          "earphoneMicActive": false,
          "earphoneMicAvailable": false,
          "phoneMicActive": false,
          "routeName": "Device speaker",
          "inputName": "Phone microphone",
        ])
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

  // MARK: - Flutter channels

  private func attachAudioRouteChannelsWhenReady(attempt: Int = 0) {
    DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay(for: attempt)) { [weak self] in
      guard let self else { return }
      if self.attachAudioRouteChannels() { return }
      if attempt < 12 {
        self.attachAudioRouteChannelsWhenReady(attempt: attempt + 1)
      } else {
        NSLog("CUE: failed to attach audio route channels after launch")
      }
    }
  }

  private func attachAudioRouteChannels() -> Bool {
    if routeChannelsAttached { return true }
    guard let messenger = audioRouteBinaryMessenger() else {
      return false
    }

    FlutterMethodChannel(
      name: routeChannelName,
      binaryMessenger: messenger
    ).setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "currentRoute":
        result(self?.currentRouteState() ?? self?.fallbackRouteState())
      case "prepareEarphoneMic":
        self?.prepareEarphoneMic()
        result(self?.currentRouteState() ?? self?.fallbackRouteState())
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    FlutterEventChannel(
      name: routeEventsChannelName,
      binaryMessenger: messenger
    ).setStreamHandler(self)

    routeChannelsAttached = true
    emitRouteState()
    return true
  }

  private func retryDelay(for attempt: Int) -> DispatchTimeInterval {
    if attempt == 0 {
      return .milliseconds(0)
    }
    return .milliseconds(250)
  }

  // MARK: - Route state

  private func currentRouteState() -> [String: Any] {
    let session = AVAudioSession.sharedInstance()
    // Check active outputs first (what audio is going to).
    let output = session.currentRoute.outputs.first(where: isEarphoneOutputPort)
    let activeInput = session.currentRoute.inputs.first(where: isEarphoneInputPort)
    let currentInput = session.currentRoute.inputs.first
    let availableInput = session.availableInputs?.first(where: isEarphoneInputPort)
    // Available input is enough to start; active input is required to continue
    // once the recorder has activated the audio session.
    let input = activeInput ?? availableInput
    let name = output?.portName ?? input?.portName ?? "Device speaker"
    let inputName = activeInput?.portName ?? availableInput?.portName ?? currentInput?.portName ?? "Phone microphone"
    return [
      "earphonesConnected": output != nil || input != nil,
      "earphoneMicActive": activeInput != nil,
      "earphoneMicAvailable": input != nil,
      "phoneMicActive": currentInput != nil && activeInput == nil,
      "routeName": name,
      "inputName": inputName,
    ]
  }

  private func fallbackRouteState() -> [String: Any] {
    return [
      "earphonesConnected": false,
      "earphoneMicActive": false,
      "earphoneMicAvailable": false,
      "phoneMicActive": false,
      "routeName": "Device speaker",
      "inputName": "Phone microphone",
    ]
  }

  private func isEarphoneOutputPort(_ p: AVAudioSessionPortDescription) -> Bool {
    switch p.portType {
    case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .headphones, .headsetMic, .usbAudio:
      return true
    default:
      return false
    }
  }

  private func isEarphoneInputPort(_ p: AVAudioSessionPortDescription) -> Bool {
    switch p.portType {
    case .bluetoothHFP, .bluetoothLE, .headsetMic, .usbAudio:
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

  private func prepareEarphoneMic() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(
        .playAndRecord,
        mode: .spokenAudio,
        options: [.allowBluetooth, .allowBluetoothA2DP]
      )
      if let input = session.availableInputs?.first(where: isEarphoneInputPort) {
        try session.setPreferredInput(input)
      }
    } catch {
      NSLog("CUE: preferred earphone mic error: \(error)")
    }
  }

  // MARK: - Messenger helper

  private func audioRouteBinaryMessenger() -> FlutterBinaryMessenger? {
    if let vc = window?.rootViewController as? FlutterViewController {
      return vc.binaryMessenger
    }
    return nil
  }
}
