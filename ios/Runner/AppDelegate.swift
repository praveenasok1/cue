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

    prepareAudioSessionForRouteMonitoring()
    guard let messenger = audioRouteBinaryMessenger() else {
      NSLog("CUE failed to attach audio route channels")
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
      result(self?.currentRouteState() ?? [
        "earphonesConnected": false,
        "routeName": "Unknown",
      ])
    }

    FlutterEventChannel(
      name: routeEventsChannelName,
      binaryMessenger: messenger
    ).setStreamHandler(self)

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(audioRouteChanged),
      name: AVAudioSession.routeChangeNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(audioRouteChanged),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    routeEventSink = events
    events(currentRouteState())
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    routeEventSink = nil
    return nil
  }

  @objc private func audioRouteChanged() {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.routeEventSink?(self.currentRouteState())
    }
  }

  private func audioRouteBinaryMessenger() -> FlutterBinaryMessenger? {
    if let controller = window?.rootViewController as? FlutterViewController {
      return controller.binaryMessenger
    }
    return registrar(forPlugin: "AudioSessionPlugin")?.messenger()
  }

  private func prepareAudioSessionForRouteMonitoring() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(
        .playAndRecord,
        mode: .spokenAudio,
        options: [.allowBluetooth, .allowBluetoothA2DP]
      )
    } catch {
      NSLog("CUE failed to configure AVAudioSession: \(error)")
    }
  }

  private func currentRouteState() -> [String: Any] {
    let session = AVAudioSession.sharedInstance()
    let output = session.currentRoute.outputs.first(where: isEarphonePort)
    let input = session.availableInputs?.first(where: isEarphonePort)
    let routeName = output?.portName ?? input?.portName ?? "Device speaker"

    return [
      "earphonesConnected": output != nil || input != nil,
      "routeName": routeName,
    ]
  }

  private func isEarphonePort(_ description: AVAudioSessionPortDescription) -> Bool {
    switch description.portType {
    case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .headphones, .headsetMic, .usbAudio:
      return true
    default:
      return false
    }
  }
}
