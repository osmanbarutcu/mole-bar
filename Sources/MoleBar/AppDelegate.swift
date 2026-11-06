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
        case "molebar.update": return .settings
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
        if StatusItemController.isEnabled() {
            let controller = StatusItemController(stats: StatsModel.shared)
            StatusItemController.shared = controller
            controller.install()
            // Geliştirme: MOLEBAR_DIAG_POPOVER=1 paneli 3 sn sonra bir kez açar. Ekran görüntüsü içindir.
            if ProcessInfo.processInfo.environment["MOLEBAR_DIAG_POPOVER"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { MainActor.assumeIsolated { PanelToggle.toggle() } }
            }
        }
        // Geliştirme: MOLEBAR_DIAG_CLOSE_MAIN=1 ana pencereyi 3 sn sonra kapatır. Uygulamanın yaşayıp yaşamadığını sınar.
        if ProcessInfo.processInfo.environment["MOLEBAR_DIAG_CLOSE_MAIN"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                for window in NSApp.windows where window.identifier?.rawValue.contains("main") == true { window.close() }
            }
        }
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

    /// Ana pencere kapanınca uygulama çıkmaz. Menü çubuğu öğesi çalışmaya devam eder. Çıkış için panelde "Çık" ya da ⌘Q kullanılır.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Dock simgesine tıklanınca görünür pencere yoksa ana pencere açılır.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NotificationCenter.default.post(name: .molebarOpenMain, object: nil) }
        return true
    }
}
