import AppKit
import Carbon
import UserNotifications

extension Notification.Name {
    /// Ana pencereyi açma isteği. Menü çubuğu etiketi dinler ve `openWindow` çağırır.
    static let molebarOpenMain = Notification.Name("molebar.openMain")
}

/// Bildirime tıklayınca açılacak sayfa. Kimlikler `DiskNotifier.post` çağrılarında verilir.
enum NotificationRoute {
    static func section(for identifier: String) -> MainSection? {
        switch identifier {
        case "molebar.cache": return .caches
        case "molebar.disk": return .disks
        case "molebar.memory": return .processes
        case "molebar.scan": return .tools
        default: return nil
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
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
        if Bundle.main.bundleIdentifier != nil { UNUserNotificationCenter.current().delegate = self }
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

    /// Uygulama öndeyken de bildirim başlığı gösterilir.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Bildirime tıklayınca ilgili sayfayı ana pencerede açar.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        DispatchQueue.main.async {
            if let section = NotificationRoute.section(for: identifier) {
                UserDefaults.standard.set(section.rawValue, forKey: "mainSection")
                NotificationCenter.default.post(name: .molebarOpenMain, object: nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            completionHandler()
        }
    }

    /// Dock simgesine tıklanınca görünür pencere yoksa ana pencere açılır.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NotificationCenter.default.post(name: .molebarOpenMain, object: nil) }
        return true
    }
}
