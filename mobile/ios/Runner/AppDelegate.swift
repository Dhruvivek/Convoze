import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // The local replica (ADR 0009) is fully rebuildable from the server, so
    // it's excluded from the iCloud/iTunes backup — `lib/core/db/backup_exclusion.dart`
    // calls this once, right after the db file is created, with its path.
    let channel = FlutterMethodChannel(
      name: "convoze/db_backup",
      binaryMessenger: engineBridge.pluginRegistry as! FlutterBinaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "excludeFromBackup",
        let path = (call.arguments as? [String: Any])?["path"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      var url = URL(fileURLWithPath: path)
      var resourceValues = URLResourceValues()
      resourceValues.isExcludedFromBackup = true
      do {
        try url.setResourceValues(resourceValues)
        result(nil)
      } catch {
        result(
          FlutterError(
            code: "exclude_from_backup_failed", message: error.localizedDescription, details: nil))
      }
    }
  }
}
