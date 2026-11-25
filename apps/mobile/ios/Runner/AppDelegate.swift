import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var microReviewChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(onMicroReviewAction(_:)),
      name: Notification.Name("AcquireMicroReviewAction"),
      object: nil
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AudioToolsPlugin") {
      AudioToolsPlugin.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "MicroReviewLiveActivity"
    ) {
      let channel = FlutterMethodChannel(
        name: "com.acquire.english/micro_review_live_activity",
        binaryMessenger: registrar.messenger()
      )
      microReviewChannel = channel
      channel.setMethodCallHandler { call, result in
        // Live Activity UI is in MicroReviewWidget (Xcode target). Until wired,
        // start returns false so Flutter keeps the in-app session card.
        switch call.method {
        case "start", "update":
          result(false)
        case "end":
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.scheme == "acquireenglish",
       url.host == "micro-review",
       let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
       let action = items.first(where: { $0.name == "action" })?.value
    {
      NotificationCenter.default.post(
        name: Notification.Name("AcquireMicroReviewAction"),
        object: nil,
        userInfo: ["action": action]
      )
    }
    return super.application(app, open: url, options: options)
  }

  @objc private func onMicroReviewAction(_ note: Notification) {
    guard let action = note.userInfo?["action"] as? String else { return }
    microReviewChannel?.invokeMethod("action", arguments: ["action": action])
  }
}
