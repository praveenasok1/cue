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

    let controller = window?.rootViewController as! FlutterViewController
    FlutterMethodChannel(
      name: routeChannelName,
      binaryMessenger: controller.binaryMessenger
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
      binaryMessenger: controller.binaryMessenger
    ).setStreamHandler(self)

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(audioRouteChanged),
      name: AVAudioSession.routeChangeNotification,
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
    routeEventSink?(currentRouteState())
  }

  private func currentRouteState() -> [String: Any] {
    let route = AVAudioSession.sharedInstance().currentRoute
    let output = route.outputs.first { output in
      switch output.portType {
      case .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
        return true
      default:
        return false
      }
    }

    return [
      "earphonesConnected": output != nil,
      "routeName": output?.portName ?? "Device speaker",
    ]
  }
}
