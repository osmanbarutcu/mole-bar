import ServiceManagement
import SwiftUI

@main
struct MoleBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var stats = StatsModel()

    init() {
        let enabled = UserDefaults.standard.object(forKey: "hotkeyEnabled") as? Bool ?? true
        if enabled { GlobalHotKey.register() }
        integrationLog.info("Giriş öğesi durumu: \(SMAppService.mainApp.status.rawValue) (0 kayıtsız, 1 açık, 2 onay bekliyor, 3 bulunamadı)")
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
        .commands {
            CommandMenu("Sayfa") {
                ForEach(MainSection.allCases) { section in
                    let open = { UserDefaults.standard.set(section.rawValue, forKey: "mainSection") }
                    if let key = section.shortcut {
                        Button(section.rawValue, action: open).keyboardShortcut(key, modifiers: .command)
                    } else {
                        Button(section.rawValue, action: open)
                    }
                }
            }
        }
    }
}

/// Menü çubuğu etiketi. Ana pencereyi açma isteğini de burada dinler, çünkü etiket her zaman canlıdır.
struct MenuBarLabel: View {
    @ObservedObject var stats: StatsModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage("displayMode") private var displayMode = "text"
    @AppStorage("graphMetric") private var graphMetric = "cpu"
    @AppStorage("showCPU") private var showCPU = true
    @AppStorage("showRAM") private var showRAM = true
    @AppStorage("showDisk") private var showDisk = true
    @AppStorage("showLabels") private var showLabels = true

    var body: some View {
        Group {
            if displayMode == "icon" {
                Image(systemName: "gauge.with.dots.needle.50percent")
            } else if displayMode == "graph" {
                let metric = GraphMetric(stored: graphMetric)
                let values = stats.recent(metric)
                HStack(spacing: 4) {
                    Image(nsImage: MenuBarGraph.image(values: values, maximum: metric.ceiling(for: values)))
                    Text(metric.label(value: values.last ?? 0)).monospacedDigit()
                }
            } else {
                Text(stats.barText(cpu: showCPU, ram: showRAM, disk: showDisk, labels: showLabels))
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(displayMode == "graph"
            ? "MoleBar, \(GraphMetric(stored: graphMetric).title) \(GraphMetric(stored: graphMetric).label(value: stats.recent(GraphMetric(stored: graphMetric)).last ?? 0))"
            : "MoleBar")
        .onReceive(NotificationCenter.default.publisher(for: .molebarOpenMain)) { _ in
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
