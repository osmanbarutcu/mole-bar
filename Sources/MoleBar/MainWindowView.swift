import SwiftUI

enum MainSection: String, CaseIterable, Identifiable {
    case general = "Genel"
    case disks = "Diskler"
    case analyze = "Analiz"
    case large = "Büyük dosyalar"
    case duplicates = "Yinelenenler"
    case apps = "Uygulamalar"
    case processes = "Süreçler"
    case tools = "Araçlar"
    case settings = "Ayarlar"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: return "gauge.with.dots.needle.50percent"
        case .disks: return "internaldrive"
        case .analyze: return "chart.pie"
        case .large: return "doc.text.magnifyingglass"
        case .duplicates: return "square.on.square"
        case .apps: return "square.stack.3d.up"
        case .processes: return "list.number"
        case .tools: return "wrench.and.screwdriver"
        case .settings: return "gearshape"
        }
    }
}

/// Çift tıklayınca açılan ana pencere. Yan menü seçimine göre panelle aynı sayfaları gösterir.
struct MainWindowView: View {
    @ObservedObject var stats: StatsModel
    @ObservedObject var preview: CleanPreview
    @AppStorage("mainSection") private var storedSection = MainSection.general.rawValue
    @StateObject private var analyzer = DiskAnalyzer()
    @StateObject private var uninstaller = AppUninstaller()
    @StateObject private var largeFinder = LargeFileFinder()
    @StateObject private var duplicateFinder = DuplicateFinder()

    var body: some View {
        let current = MainSection(rawValue: storedSection) ?? .general
        let selection = Binding<MainSection?>(
            get: { current },
            set: { storedSection = ($0 ?? .general).rawValue }
        )
        NavigationSplitView {
            List(MainSection.allCases, selection: selection) { section in
                Label(section.rawValue, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            Group {
                if current == .analyze {
                    AnalyzePage(analyzer: analyzer, volumes: stats.volumes)
                } else if current == .large {
                    LargeFilesPage(finder: largeFinder)
                } else if current == .duplicates {
                    DuplicatesPage(finder: duplicateFinder)
                } else if current == .apps {
                    UninstallPage(model: uninstaller)
                } else {
                    PanelView(stats: stats, preview: preview, embedded: current)
                        .id(current)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationTitle(current.rawValue)
        .navigationSubtitle("MoleBar")
        .frame(minWidth: 820, minHeight: 560)
    }
}
