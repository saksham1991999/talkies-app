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
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TalkiesAppIcon") else { return }
    // Alternate launcher icons: asset catalog sets named AppIcon-<variant>.
    let channel = FlutterMethodChannel(name: "talkies/app_icon", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "set",
            let args = call.arguments as? [String: Any],
            let name = args["name"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard UIApplication.shared.supportsAlternateIcons else {
        result(false)
        return
      }
      UIApplication.shared.setAlternateIconName(name == "default" ? nil : "AppIcon-\(name)") { error in
        result(error == nil)
      }
    }
  }
}
