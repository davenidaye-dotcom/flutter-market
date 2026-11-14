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
    let channel = FlutterMethodChannel(
      name: "flyroom/shield",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "init":
        result(Self.shieldInit())
      case "localPort":
        result(Self.shieldLocalPort())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func shieldSecrets() -> (String, String)? {
    let key = Bundle.main.object(forInfoDictionaryKey: "ShieldAccessKey") as? String ?? ""
    let uuid = Bundle.main.object(forInfoDictionaryKey: "ShieldUuid") as? String ?? ""
    if key.isEmpty || uuid.isEmpty || key.contains("$(") || uuid.contains("$(") {
      return nil
    }
    return (key, uuid)
  }

  private static func shieldInit() -> Bool {
    guard let (key, uuid) = shieldSecrets() else { return false }
    return ShieldInit(key, uuid) == 0
  }

  private static func shieldLocalPort() -> [String: Any]? {
    guard shieldSecrets() != nil else { return nil }
    var ip = [CChar](repeating: 0, count: 32)
    var port: Int32 = -1
    let rc = ip.withUnsafeMutableBufferPointer { buf in
      ShieldLocalPort(buf.baseAddress, 32, &port)
    }
    let text = String(cString: ip)
    if rc != 0 || port <= 0 || text.isEmpty {
      return nil
    }
    return ["ip": text, "port": Int(port)]
  }
}
