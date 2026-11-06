import AppKit
import Carbon

extension Notification.Name {
    /// Ana pencereyi açma isteği. Menü çubuğu etiketi dinler ve `openWindow` çağırır.
    static let molebarOpenMain = Notification.Name("molebar.openMain")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// "system" sistem temasını izler. "light" ve "dark" uygulamayı o temaya sabitler.
    static func applyAppearance(_ value: String) {
        switch value {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.applyAppearance(UserDefaults.standard.string(forKey: "appearance") ?? "system")
        // Giriş öğesi olarak başlatıldıysa pencere açılmaz, yalnızca menü çubuğu kalır.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
            == OSType(keyAELaunchedAsLogInItem)
        guard launchedAtLogin else { return }
        DispatchQueue.main.async {
            for window in NSApp.windows where window.identifier?.rawValue.contains("main") == true {
                window.close()
            }
        }
    }

    /// Dock simgesine tıklanınca görünür pencere yoksa ana pencere açılır.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NotificationCenter.default.post(name: .molebarOpenMain, object: nil) }
        return true
    }
}
