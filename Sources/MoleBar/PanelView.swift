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
    @StateObject private var loginItem = LoginItem()
    @AppStorage("hotkeyEnabled") private var hotkeyEnabled = true
    @AppStorage("weeklyScan") private var weeklyScan = false
    @AppStorage("displayMode") private var displayMode = "text"
    @AppStorage("showCPU") private var showCPU = true
    @AppStorage("showRAM") private var showRAM = true
    @AppStorage("showDisk") private var showDisk = true
    @AppStorage("showLabels") private var showLabels = true
    @AppStorage("diskAlertEnabled") private var diskAlertEnabled = true
    @AppStorage("diskAlertThreshold") private var diskAlertThreshold = 90
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
            VStack(alignment: .leading, spacing: 12) {
                Button { layout.showPreview = false } label: { Label("Geri", systemImage: "chevron.left") }
                    .glassButton()
                Text(preview.job.title).font(.title2.weight(.semibold))
                CleanPreviewPage(preview: preview)
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
        } else if section == .settings {
            settingsPage
                .padding(20)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView {
                GlassGroup(spacing: 12) {
                    VStack(spacing: 12) {
                        switch section {
                        case .general: generalPage
                        case .disks: disksPage
                        case .processes: processesPage
                        case .tools: toolsPage
                        case .settings, .analyze, .apps, .large: EmptyView()
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 760)
            }
            .scrollClipDisabled()
        }
    }

    private var panelBody: some View {
        VStack(spacing: 10) {
            header
            if layout.showPreview {
                CleanPreviewPage(preview: preview)
            } else if layout.showSettings {
                settingsPage
            } else {
                Picker("Sekme", selection: $layout.tab) {
                    ForEach(PanelTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                ScrollView(showsIndicators: false) {
                    GlassGroup(spacing: 12) {
                        VStack(spacing: 10) {
                            switch layout.tab {
                            case .general: generalPage
                            case .disks: disksPage
                            case .processes: processesPage
                            case .tools: toolsPage
                            }
                        }
                    }
                }
            }
            footer
        }
        .padding(12)
        .frame(width: 344, height: panelHeight)
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
            Button("Çık") { NSApplication.shared.terminate(nil) }
                .glassButton()
                .keyboardShortcut("q")
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
            historyCard
            memoryCard
            HStack(spacing: 8) {
                RateChip(symbol: "arrow.down.circle", label: "İndirme", value: formatRate(stats.netDown))
                RateChip(symbol: "arrow.up.circle", label: "Yükleme", value: formatRate(stats.netUp))
            }
        }
    }

    @ViewBuilder
    private var healthCard: some View {
        if let health = stats.health {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(symbol: "heart.text.square", title: "Sistem sağlığı (Mole)", trailing: "\(health.score)/100")
                UsageBar(percent: Double(health.score), color: healthColor(health.score))
                Text(health.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
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
        .padding(12)
        .glassCard()
    }

    private var memoryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(symbol: "memorychip", title: "Bellek", trailing: String(format: "%.0f%%", stats.memory.percent))
            UsageBar(percent: stats.memory.percent)
            Text("\(formatBytes(stats.memory.usedBytes)) / \(formatBytes(stats.memory.totalBytes))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: Diskler

    private var disksPage: some View {
        Group {
            if stats.diskAlert { diskAlertBanner }
            volumesCard
            Button { openPreview() } label: {
                Label("Temizlik önizlemesi", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .glassProminentButton()
            .controlSize(.large)
            HStack(spacing: 8) {
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
                toolRow(symbol: "trash.slash", title: "Temizlik", detail: "Önizleme, sonra onaylı temizlik") {
                    openPreview(.cleanPreview)
                }
                toolRow(symbol: "chart.pie", title: "Disk analizi", detail: "Klasör boyutları, büyük pencerede") {
                    UserDefaults.standard.set(MainSection.analyze.rawValue, forKey: "mainSection")
                    NotificationCenter.default.post(name: .molebarOpenMain, object: nil)
                }
                toolRow(symbol: "wrench.and.screwdriver", title: "Bakım (optimize)", detail: "Önizleme. Çalıştırma Terminal'de") {
                    openPreview(.optimizePreview)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()

            VStack(alignment: .leading, spacing: 10) {
                CardHeader(symbol: "terminal", title: "Terminal'de aç")
                toolRow(symbol: "chart.pie", title: "Disk analizi (TUI)", detail: "mo analyze") { TerminalBridge.run("mo analyze") }
                toolRow(symbol: "app.badge.checkmark", title: "Uygulama kaldır", detail: "mo uninstall") { TerminalBridge.run("mo uninstall") }
                toolRow(symbol: "folder.badge.minus", title: "Proje artıkları", detail: "mo purge (upstream hata, doğrulanmadı)") { TerminalBridge.run("mo purge") }
                toolRow(symbol: "shippingbox", title: "Kurulum dosyaları", detail: "mo installer") { TerminalBridge.run("mo installer") }
                toolRow(symbol: "touchid", title: "Touch ID ile sudo", detail: "mo touchid") { TerminalBridge.run("mo touchid") }
                toolRow(symbol: "lock.shield", title: "Korunan yollar", detail: "mo clean --whitelist. Varsayılan korumaları da yönetir") {
                    TerminalBridge.run("mo clean --whitelist")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
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

    // MARK: Geçmiş

    @ViewBuilder
    private var historyCard: some View {
        if stats.history.count > 1 {
            let cpu = stats.history.map(\.cpu)
            let ram = stats.history.map(\.memory)
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(
                    symbol: "chart.xyaxis.line",
                    title: "Geçmiş",
                    trailing: "son \(max(stats.history.count / 2, 1)) dk"
                )
                Sparkline(values: cpu, color: .blue)
                    .frame(height: 38)
                Sparkline(values: ram, color: .purple)
                    .frame(height: 38)
                HStack(spacing: 12) {
                    legend("CPU", color: .blue, average: cpu.reduce(0, +) / Double(cpu.count))
                    legend("RAM", color: .purple, average: ram.reduce(0, +) / Double(ram.count))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    private func legend(_ name: String, color: Color, average: Double) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(String(format: "%@ ort. %.0f%%", name, average))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
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
        .padding(12)
        .glassCard(tint: .orange)
    }

    private var volumesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: Süreçler

    private var processesPage: some View {
        let rows = topProcesses
        let peak = max(rows.map { procSort == "cpu" ? $0.cpu : Double($0.memoryBytes) }.max() ?? 1, 0.0001)
        return VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "list.number", title: "En çok kullanan 10")
            Picker("Sıralama", selection: $procSort) {
                Text("CPU").tag("cpu")
                Text("Bellek").tag("mem")
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if rows.isEmpty {
                Text("Süreç verisi toplanıyor…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(rows) { processRow($0, peak: peak) }

            Text("Aynı uygulamanın süreçleri toplanır. Bellek, çalışan küme (RSS) değeridir.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var topProcesses: [ProcessGroup] {
        let sorted = procSort == "cpu"
            ? stats.processGroups.sorted { $0.cpu > $1.cpu }
            : stats.processGroups.sorted { $0.memoryBytes > $1.memoryBytes }
        return Array(sorted.prefix(10))
    }

    private func processRow(_ row: ProcessGroup, peak: Double) -> some View {
        let value = procSort == "cpu" ? row.cpu : Double(row.memoryBytes)
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
                Text(procSort == "cpu" ? String(format: "%.1f%%", row.cpu) : formatBytes(row.memoryBytes))
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
            } else if layout.pendingKill != row.id {
                Color.clear.frame(width: 16, height: 1)
            }
        }
    }

    // MARK: Ayarlar

    private var settingsPage: some View {
        ScrollView(showsIndicators: false) {
            GlassGroup(spacing: 12) {
                VStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 10) {
                        CardHeader(symbol: "menubar.rectangle", title: "Menü çubuğu")
                        Picker("Görünüm", selection: $displayMode) {
                            Text("Metin").tag("text")
                            Text("İkon").tag("icon")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 10) {
                        CardHeader(symbol: "textformat.123", title: "Metin modunda göster")
                        Toggle("CPU", isOn: $showCPU)
                        Toggle("RAM", isOn: $showRAM)
                        Toggle("Disk", isOn: $showDisk)
                        Toggle("Etiketler", isOn: $showLabels)
                    }
                    .toggleStyle(RightSwitchStyle())
                    .controlSize(.small)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                    .disabled(displayMode == "icon")
                    .opacity(displayMode == "icon" ? 0.5 : 1)

                    VStack(alignment: .leading, spacing: 10) {
                        CardHeader(symbol: "power", title: "Başlatma ve kısayol")
                        Toggle("Girişte başlat", isOn: Binding(
                            get: { loginItem.isEnabled },
                            set: { loginItem.set($0) }
                        ))
                        if let error = loginItem.errorText {
                            Text(error).font(.caption2).foregroundStyle(.red)
                        }
                        Toggle("Kısayol ⌥⌘M ile paneli aç", isOn: Binding(
                            get: { hotkeyEnabled },
                            set: { value in
                                hotkeyEnabled = value
                                if value { GlobalHotKey.register() } else { GlobalHotKey.unregister() }
                            }
                        ))
                        Toggle("Haftalık otomatik tarama", isOn: $weeklyScan)
                        Text("Tarama yalnızca önizlemedir ve sonucu bildirir. Hiçbir şey silmez. Uygulama açıkken çalışır.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .toggleStyle(RightSwitchStyle())
                    .controlSize(.small)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 10) {
                        CardHeader(symbol: "bell.badge", title: "Disk uyarısı")
                        Toggle("Eşik aşılınca bildir", isOn: $diskAlertEnabled)
                            .toggleStyle(RightSwitchStyle())
                            .controlSize(.small)
                        Stepper("Eşik: %\(diskAlertThreshold)", value: $diskAlertThreshold, in: 70...98)
                            .disabled(!diskAlertEnabled)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                }
            }
        }
    }
}
