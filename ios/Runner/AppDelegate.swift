import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    provideGoogleMapsAPIKey()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  /// Reads IOS_MAPS_API_KEY from the bundled dev/.env asset and activates
  /// Google Maps. Never crashes — a missing/empty key just leaves the admin
  /// live staff map blank.
  private func provideGoogleMapsAPIKey() {
    let assetKey = FlutterDartProject.lookupKey(forAsset: "dev/.env")
    guard let path = Bundle.main.path(forResource: assetKey, ofType: nil),
      let contents = try? String(contentsOfFile: path, encoding: .utf8)
    else {
      NSLog("IOS_MAPS_API_KEY missing — live map will be blank")
      return
    }
    let prefix = "IOS_MAPS_API_KEY="
    guard
      let line = contents.split(separator: "\n").first(where: { $0.hasPrefix(prefix) })
    else {
      NSLog("IOS_MAPS_API_KEY missing — live map will be blank")
      return
    }
    let rawValue = line.dropFirst(prefix.count)
    let key = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: " \"'\t"))
    guard !key.isEmpty else {
      NSLog("IOS_MAPS_API_KEY missing — live map will be blank")
      return
    }
    GMSServices.provideAPIKey(key)
  }
}
