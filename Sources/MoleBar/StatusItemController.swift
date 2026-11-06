import AppKit
import Combine
import SwiftUI

/// Menü çubuğu düğmesinin içeriği: metin, ikon veya grafik.
struct StatusItemContent: Equatable {
    var title: String
    var showsIcon: Bool
    var showsGraph: Bool

    /// Bilinmeyen kip metin olarak ele alınır. Grafik kipinde başlık, seçili ölçümün etiketidir.
    static func resolve(displayMode: String, barText: String, graphLabel: String) -> StatusItemContent {
        switch displayMode {
        case "icon": return StatusItemContent(title: "", showsIcon: true, showsGraph: false)
        case "graph": return StatusItemContent(title: graphLabel, showsIcon: false, showsGraph: true)
        default: return StatusItemContent(title: barText, showsIcon: false, showsGraph: false)
        }
    }
}

/// Deneysel: SwiftUI `MenuBarExtra` yerine kendi `NSStatusItem` ve `NSPopover` öğemiz.
/// macOS 27'de `MenuBarExtra` paneli koddan açılamaz. Kendi öğemizde ⌥⌘M paneli açıp kapatır.
/// Varsayılan kapalıdır. Ayarlar'da açılır ve uygulamanın yeniden başlatılmasını gerektirir.
@MainActor
final class StatusItemController: NSObject {
    nonisolated static let defaultsKey = "customStatusItem"
    static var shared: StatusItemController?

    nonisolated static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }

    private let stats: StatsModel
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var subscription: AnyCancellable?

    var isInstalled: Bool { statusItem != nil }

    init(stats: StatsModel) {
        self.stats = stats
        super.init()
    }

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(buttonClicked)
        item.button?.sendAction(on: [.leftMouseUp])
        statusItem = item

        let host = NSHostingController(rootView: PanelView(stats: stats, preview: stats.cleanPreview))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true

        refresh()
        subscription = stats.objectWillChange
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        integrationLog.info("Özel durum çubuğu öğesi kuruldu")
    }

    func uninstall() {
        popover.performClose(nil)
        subscription = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    @objc private func buttonClicked() { toggle() }

    func toggle() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Şeffaf pencere tuş penceresi olmazsa dışarı tıklayınca kapanmaz.
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Düğme başlığını ve görüntüsünü kayıtlı ayarlara göre günceller.
    private func refresh() {
        guard let button = statusItem?.button else { return }
        let defaults = UserDefaults.standard
        func flag(_ key: String, _ fallback: Bool = true) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        let metric = GraphMetric(stored: defaults.string(forKey: "graphMetric") ?? "cpu")
        let values = stats.recent(metric)
        let content = StatusItemContent.resolve(
            displayMode: defaults.string(forKey: "displayMode") ?? "text",
            barText: stats.barText(cpu: flag("showCPU"), ram: flag("showRAM"), disk: flag("showDisk"), labels: flag("showLabels")),
            graphLabel: metric.label(value: values.last ?? 0)
        )
        button.title = content.title
        button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        if content.showsIcon {
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: "MoleBar")
        } else if content.showsGraph {
            button.image = MenuBarGraph.image(values: values, maximum: metric.ceiling(for: values))
        } else {
            button.image = nil
        }
        button.imagePosition = content.title.isEmpty ? .imageOnly : .imageLeading
        button.setAccessibilityLabel(content.title.isEmpty ? "MoleBar" : "MoleBar, \(content.title)")
    }
}
