import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    registerNativeConfigChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func registerNativeConfigChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      NSLog("Native config channel unavailable")
      return
    }
    let channel = FlutterMethodChannel(
      name: "net.vogas.scheduling/native_config",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "provideGoogleMapsApiKey" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let key = call.arguments as? String, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        NSLog("IOS_MAPS_API_KEY missing - live map will be blank")
        result(nil)
        return
      }
      GMSServices.provideAPIKey(key)
      result(nil)
    }
  }
}
