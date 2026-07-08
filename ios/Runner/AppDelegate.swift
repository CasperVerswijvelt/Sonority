import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let channelName = "be.casperverswijvelt.sonority/shortcuts"
  private var channel: FlutterMethodChannel?
  // Profile id of the shortcut that cold-started the app, pulled by Dart via
  // `getInitialShortcut` once the engine is ready.
  private var launchShortcutId: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: controller.binaryMessenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "setShortcuts":
        self?.setShortcuts(call.arguments)
        result(nil)
      case "getInitialShortcut":
        result(self?.launchShortcutId)
        self?.launchShortcutId = nil
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Launched from a shortcut? Stash it and return false so the system doesn't
    // also call performActionFor for the same launch (Dart pulls it instead).
    if let item = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
      launchShortcutId = item.type
      _ = super.application(application, didFinishLaunchingWithOptions: launchOptions)
      return false
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Warm tap (app running / backgrounded): hand the id straight to Dart.
  override func application(
    _ application: UIApplication,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    channel?.invokeMethod("applyShortcut", arguments: shortcutItem.type)
    completionHandler(true)
  }

  private func setShortcuts(_ arguments: Any?) {
    guard let map = arguments as? [String: Any],
      let items = map["items"] as? [[String: Any]]
    else { return }
    UIApplication.shared.shortcutItems = items.compactMap { item in
      guard let id = item["id"] as? String, let title = item["title"] as? String
      else { return nil }
      var icon: UIApplicationShortcutIcon?
      if let symbol = item["sfSymbol"] as? String {
        icon = UIApplicationShortcutIcon(systemImageName: symbol)
      }
      return UIApplicationShortcutItem(
        type: id, localizedTitle: title, localizedSubtitle: nil, icon: icon,
        userInfo: nil)
    }
  }
}
