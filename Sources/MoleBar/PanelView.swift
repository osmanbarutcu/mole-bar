import SwiftUI

enum PanelTab: String, CaseIterable, Identifiable {
    case general = "Genel"
    case disks = "Diskler"
    case processes = "Süreçler"
    case tools = "Araçlar"
    var id: String { rawValue }
}

/// Panel sayfa durumu. Panel yüksekliği sabittir, sekme değişince pencere boyutlanmaz.
@MainActor
final class PanelLayout: ObservableObject {
    @Published var showSettings = false
    @Published var showPreview = false
    @Published var tab: PanelTab = PanelTab(rawValue: UserDefaults.standard.string(forKey: "panelTab") ?? "") ?? .general {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: "panelTab") }
    }
    @Published var pendingKill: String?
}

struct PanelView: View {
    @ObservedObject var stats: StatsModel
    @StateObject private var layout = PanelLayout()
    @ObservedObject var preview: CleanPreview
    /// Doluysa ana pencerede gömülü çalışır: üst çubuk, sekme seçici ve sabit boyut yoktur.
    var embedded: MainSection? = nil
    @AppStorage("procSort") private var procSort = "cpu"

    private let panelHeight: CGFloat = 620

    var body: some View {
        if let section = embedded {
            embeddedBody(section)
        } else {
            panelBody
        }
    }

    @ViewBuilder
    private func embeddedBody(_ section: MainSection) -> some View {
        if layout.showPreview {
            VStack(alignment: .leading, spacing: 14) {
                Button { layout.showPreview = false } label: { Label("Geri", systemImage: "chevron.left") }
                    .glassButton()
                Text(preview.job.title).font(.title2.weight(.semibold))
                CleanPreviewPage(preview: preview)
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        } else if section == .settings {
            PanelSettingsPage(stats: stats)
                .padding(24)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView {
                GlassGroup(spacing: 12) {
                    VStack(spacing: 14) {
                        switch section {
                        case .general: generalPage
                        case .disks: disksPage
                        case .processes: processesPage
                        case .tools: toolsPage
                        case .settings, .analyze, .apps, .large, .duplicates, .caches, .projects: EmptyView()
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 760)
            }
            .shadowSafeScroll(vertical: 0) // İçerik zaten padding(24) taşıyor.
        }
    }

    private var panelBody: some View {
        VStack(spacing: 14) {
            header
            if layout.showPreview {
                CleanPreviewPage(preview: preview)
            } else if layout.showSettings {
                PanelSettingsPage(stats: stats)
            } else {
                Picker("Sekme", selection: $layout.tab) {
                    ForEach(PanelTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                ScrollView(showsIndicators: false) {
                    GlassGroup(spacing: 12) {
                        VStack(spacing: 14) {
                            switch layout.tab {
                            case .general: generalPage
                            case .disks: disksPage
                            case .processes: processesPage
                            case .tools: toolsPage
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .shadowSafeScroll(vertical: 0) // İçerik zaten dikey padding(8) taşıyor.
            }
            footer
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(width: 344, height: panelHeight)
        .background(Color(nsColor: .controlBackgroundColor))
        .transaction { $0.animation = nil }
    }

    // MARK: Üst ve alt çubuk

    private var header: some View {
        HStack {
            if layout.showSettings || layout.showPreview {
                Button {
                    layout.showSettings = false
                    layout.showPreview = false
                } label: { Image(systemName: "chevron.left") }
                    .glassButton()
                    .help("Geri")
                    .accessibilityLabel("Geri")
                Text(layout.showPreview ? preview.job.title : "Ayarlar").font(.headline)
            } else {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("MoleBar").font(.headline)
            }
            Spacer()
            if !layout.showSettings && !layout.showPreview {
                Button { layout.showSettings = true } label: { Image(systemName: "gearshape") }
                    .glassButton()
                    .help("Ayarlar")
                    .accessibilityLabel("Ayarlar")
            }
        }
        .padding(.horizontal, 4)
    }

    private var footer: some View {
        HStack {
            Button {
                NotificationCenter.default.post(name: .molebarOpenMain, object: nil)
            } label: { Label("Pencere", systemImage: "macwindow") }
                .glassButton()
                .help("Büyük pencereyi aç")
            Spacer()
            Button("Çık") {
                QuitPolicy.shared.allowQuit()
                NSApplication.shared.terminate(nil)
            }
                .glassButton()
                .help("MoleBar'ı tamamen kapatır. ⌘Q yalnızca pencereleri kapatır.")
        }
    }

    // MARK: Genel

    private var generalPage: some View {
        Group {
            HStack(spacing: 10) {
                RingGauge(title: "CPU", percent: stats.cpuTotal)
                RingGauge(title: "Bellek", percent: stats.memory.percent)
                RingGauge(title: "Disk", percent: stats.disk.percent)
            }
            healthCard
            coresCard
            HistoryCard(stats: stats)
            memoryCard
            SystemInfoCard(info: stats.systemInfo, health: stats.batteryHealth, sensors: stats.sensors)
            HStack(spacing: 12) {
                RateChip(symbol: "arrow.down.circle", label: "İndirme", value: formatRate(stats.netDown))
                RateChip(symbol: "arrow.up.circle", label: "Yükleme", value: formatRate(stats.netUp))
            }
        }
    }

    @ViewBuilder
    private var healthCard: some View {
        if let health = stats.health {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(symbol: "heart.text.square", title: "Sistem sağlığı (Mole)", trailing: "\(health.score)/100")
                UsageBar(percent: Double(health.score), color: healthColor(health.score))
                Text(health.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if health.score < 80 {
                    ForEach(healthHints, id: \.title) { hint in
                        HStack(spacing: 8) {
                            Image(systemName: hint.symbol).frame(width: 18).foregroundStyle(.secondary)
                            Text(hint.title).font(.caption)
                            Spacer(minLength: 8)
                            Button(hint.action) { openMain(hint.section) }
                                .glassButton()
                                .controlSize(.small)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    /// Skor 80 altındayken canlı ölçümlerden öneri çıkarır. Eşikler: disk 80, bellek 85, CPU 80 (yüzde).
    private var healthHints: [(symbol: String, title: String, action: String, section: MainSection)] {
        var hints: [(symbol: String, title: String, action: String, section: MainSection)] = []
        if stats.disk.percent >= 80 {
            hints.append(("internaldrive", String(format: "Disk %%%.0f dolu", stats.disk.percent), "Diskler", .disks))
        }
        if stats.memory.percent >= 85 {
            hints.append(("memorychip", String(format: "Bellek %%%.0f dolu", stats.memory.percent), "Süreçler", .processes))
        } else if stats.pressure.needsAttention {
            hints.append(("memorychip", "Bellek baskısı: \(stats.pressure.label)", "Süreçler", .processes))
        }
        if stats.cpuTotal >= 80 {
            hints.append(("cpu", String(format: "CPU %%%.0f yüklü", stats.cpuTotal), "Süreçler", .processes))
        }
        return hints
    }

    private func healthColor(_ score: Int) -> Color {
        score >= 80 ? .green : (score >= 60 ? .orange : .red)
    }

    private var coresCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(
                symbol: "cpu",
                title: "Çekirdekler",
                trailing: String(format: "%.0f%% toplam · %d çekirdek", stats.cpuTotal, stats.cpuPerCore.count)
            )
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(stats.cpuPerCore.enumerated()), id: \.offset) { index, usage in
                    CoreBar(index: index, percent: usage)
                }
            }
        }
        .padding(16)
        .glassCard()
    }

    private var memoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "memorychip", title: "Bellek", trailing: String(format: "%.0f%%", stats.memory.percent))
            UsageBar(percent: stats.memory.percent)
            Text("\(formatBytes(stats.memory.usedBytes)) / \(formatBytes(stats.memory.totalBytes))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            HStack {
                Text("Baskı").font(.caption).foregroundStyle(.secondary)
                Text(stats.pressure.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(stats.pressure == .critical ? Color.red : (stats.pressure == .warning ? Color.orange : Color.green))
                Spacer(minLength: 8)
                Text("Swap \(formatBytes(stats.swap.usedBytes)) / \(formatBytes(stats.swap.totalBytes))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: Diskler

    private var disksPage: some View {
        Group {
            if stats.diskAlert { diskAlertBanner }
            volumesCard
            DiskExplainerCard(cleaner: stats.cacheCleaner) { section in
                UserDefaults.standard.set(section.rawValue, forKey: "mainSection")
                NotificationCenter.default.post(name: .molebarOpenMain, object: nil)
            }
            DiskGrowthCard()
            ReclaimCard { section in
                UserDefaults.standard.set(section.rawValue, forKey: "mainSection")
                NotificationCenter.default.post(name: .molebarOpenMain, object: nil)
            }
            QuickCleanCard(cleaner: stats.cacheCleaner) { openMain(.caches) }
            Button { openPreview() } label: {
                Label("Mole temizlik önizlemesi", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .glassProminentButton()
            .controlSize(.large)
            HStack(spacing: 12) {
                RateChip(symbol: "arrow.down.doc", label: "Disk okuma", value: formatRate(stats.diskRead))
                RateChip(symbol: "arrow.up.doc", label: "Disk yazma", value: formatRate(stats.diskWrite))
            }
        }
    }

    /// Önizleme sayfasını açar. Sonuç varsa korur, yoksa taramayı başlatır.
    private func openPreview(_ job: MoleJob = .cleanPreview) {
        layout.showPreview = true
        guard preview.phase != .running else { return }
        if preview.phase == .idle || preview.phase == .failed || preview.job != job { preview.start(job) }
    }

    // MARK: Araçlar

    private var toolsPage: some View {
        Group {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(symbol: "sparkles", title: "Uygulama içinde")
                toolRow(symbol: "trash.slash", title: "Mole temizliği", detail: "mo clean önizlemesi, sonra onaylı temizlik") {
                    openPreview(.cleanPreview)
                }
                toolRow(symbol: "chart.pie", title: "Disk analizi", detail: "Klasör boyutları, büyük pencerede") { openMain(.analyze) }
                toolRow(symbol: "doc.text.magnifyingglass", title: "Büyük dosyalar", detail: "Eşik üstü dosyalar, büyük pencerede") { openMain(.large) }
                toolRow(symbol: "square.on.square", title: "Yinelenen dosyalar", detail: "Aynı içerikli kopyalar, büyük pencerede") { openMain(.duplicates) }
                toolRow(symbol: "archivebox", title: "Önbellek ve Çöp Kutusu", detail: "Önbellek listesi, büyük pencerede") { openMain(.caches) }
                toolRow(symbol: "square.stack.3d.up", title: "Uygulamalar", detail: "Kaldırma ve artık dosyalar, büyük pencerede") { openMain(.apps) }
                toolRow(symbol: "wrench.and.screwdriver", title: "Bakım (optimize)", detail: "Önizleme. Çalıştırma Terminal'de") {
                    openPreview(.optimizePreview)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()

            VStack(alignment: .leading, spacing: 10) {
                CardHeader(symbol: "terminal", title: "Terminal'de aç")
                toolRow(symbol: "chart.pie", title: "Disk analizi (TUI)", detail: "mo analyze") { TerminalBridge.run("mo analyze") }
                toolRow(symbol: "app.badge.checkmark", title: "Uygulama kaldır (Mole)", detail: "mo uninstall") { TerminalBridge.run("mo uninstall") }
                toolRow(symbol: "folder.badge.minus", title: "Proje artıkları", detail: "mo purge (upstream hata, doğrulanmadı)") { TerminalBridge.run("mo purge") }
                toolRow(symbol: "shippingbox", title: "Kurulum dosyaları", detail: "mo installer") { TerminalBridge.run("mo installer") }
                toolRow(symbol: "touchid", title: "Touch ID ile sudo", detail: "mo touchid") { TerminalBridge.run("mo touchid") }
                toolRow(symbol: "lock.shield", title: "Korunan yollar", detail: "mo clean --whitelist. Varsayılan korumaları da yönetir") {
                    TerminalBridge.run("mo clean --whitelist")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            LoginItemAuditCard()
            LaunchItemsCard()
            SecurityCard()
            NetworkInterfacesCard()
            DNSLookupCard()
            NetworkSpeedCard()
            NetworkMaintenanceCard()
            PortScanCard()
            ConnectionCard()
            HomebrewCard()
        }
    }

    /// Ana pencereyi verilen bölümde açar.
    private func openMain(_ section: MainSection) {
        UserDefaults.standard.set(section.rawValue, forKey: "mainSection")
        NotificationCenter.default.post(name: .molebarOpenMain, object: nil)
    }

    private func toolRow(symbol: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.subheadline).lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Button("Aç", action: action)
                .glassButton()
                .controlSize(.small)
        }
    }

    private var diskAlertBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(String(format: "Ana disk %%%.0f dolu", stats.disk.percent))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Button("Önizle") { openPreview() }
                .glassButton()
                .controlSize(.small)
                .help("Uygulama içinde tarar. Hiçbir şey silmez.")
        }
        .padding(16)
        .glassCard(tint: .orange)
    }

    private var volumesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(symbol: "internaldrive", title: "Diskler", trailing: "\(stats.volumes.count) birim")
            ForEach(stats.volumes) { volume in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: volume.isInternal ? "internaldrive.fill" : "externaldrive.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(volume.name)
                            .font(.subheadline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        Text(String(format: "%.0f%%", volume.percent))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(levelColor(volume.percent))
                            .fixedSize()
                    }
                    UsageBar(percent: volume.percent, height: 5)
                    Text("\(formatBytes(volume.freeBytes)) boş · toplam \(formatBytes(volume.totalBytes))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: Süreçler

    private var processesPage: some View {
        let rows = topProcesses
        let peak = max(rows.map { metric($0) }.max() ?? 1, 0.0001)
        return VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "list.number", title: "En çok kullanan 10")
            Picker("Sıralama", selection: $procSort) {
                Text("CPU").tag("cpu")
                Text("Bellek").tag("mem")
                Text("Ağ").tag("net")
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if rows.isEmpty {
                Text("Süreç verisi toplanıyor…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(rows) { processRow($0, peak: peak) }

            Text("Aynı uygulamanın süreçleri toplanır. Bellek, çalışan küme (RSS) değeridir. Ağ değeri 6 saniyede bir yenilenir.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var topProcesses: [ProcessGroup] {
        Array(stats.processGroups.sorted { metric($0) > metric($1) }.prefix(10))
    }

    /// Seçili sıralamaya göre satırın değeri.
    private func metric(_ row: ProcessGroup) -> Double {
        switch procSort {
        case "mem": return Double(row.memoryBytes)
        case "net": return row.pids.reduce(0) { $0 + (stats.netByPid[$1] ?? 0) }
        default: return row.cpu
        }
    }

    private func metricText(_ row: ProcessGroup) -> String {
        switch procSort {
        case "mem": return formatBytes(row.memoryBytes)
        case "net": return formatRate(metric(row))
        default: return String(format: "%.1f%%", row.cpu)
        }
    }

    private func processRow(_ row: ProcessGroup, peak: Double) -> some View {
        let value = metric(row)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(row.name)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if row.pids.count > 1 {
                    Text("\(row.pids.count) süreç")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)

            if layout.pendingKill == row.id {
                Button("Sonlandır") {
                    row.terminate()
                    layout.pendingKill = nil
                }
                .glassButton()
                .controlSize(.small)
                .fixedSize()
                Button("Vazgeç") { layout.pendingKill = nil }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            } else {
                UsageBar(percent: value / peak * 100, height: 4, color: .accentColor)
                    .frame(width: 56)
                Text(metricText(row))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(minWidth: 58, alignment: .trailing)
            }

            if layout.pendingKill != row.id, row.killable {
                Button { layout.pendingKill = row.id } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Sonlandır")
                    .accessibilityLabel("Sonlandır")
            } else if layout.pendingKill != row.id {
                Color.clear.frame(width: 16, height: 1)
            }
        }
    }

}
