import SwiftUI

@main
struct MoleBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var stats = StatsModel()

    init() {
        let enabled = UserDefaults.standard.object(forKey: "hotkeyEnabled") as? Bool ?? true
        if enabled { GlobalHotKey.register() }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(stats: stats, preview: stats.cleanPreview)
        } label: {
            MenuBarLabel(stats: stats)
        }
        .menuBarExtraStyle(.window)

        Window("MoleBar", id: "main") {
            MainWindowView(stats: stats, preview: stats.cleanPreview)
        }
        .defaultSize(width: 920, height: 680)
        .defaultLaunchBehavior(.presented)
    }
}

/// Menü çubuğu etiketi. Ana pencereyi açma isteğini de burada dinler, çünkü etiket her zaman canlıdır.
struct MenuBarLabel: View {
    @ObservedObject var stats: StatsModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage("displayMode") private var displayMode = "text"
    @AppStorage("showCPU") private var showCPU = true
    @AppStorage("showRAM") private var showRAM = true
    @AppStorage("showDisk") private var showDisk = true
    @AppStorage("showLabels") private var showLabels = true

    var body: some View {
        Group {
            if displayMode == "icon" {
                Image(systemName: "gauge.with.dots.needle.50percent")
            } else {
                Text(stats.barText(cpu: showCPU, ram: showRAM, disk: showDisk, labels: showLabels))
                    .monospacedDigit()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .molebarOpenMain)) { _ in
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
