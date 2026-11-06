import SwiftUI

struct PreviewLine: Identifiable {
    enum Kind { case section, item, ok, note }
    let id: Int
    let kind: Kind
    let text: String
    var size: String?
}

/// Uygulama içinde çalışan Mole işleri.
/// `cleanRun` gerçekten siler (yalnızca kullanıcı seviyesi). `optimize` gerçek çalıştırması sudo gerektirir, Terminal'de kalır.
enum MoleJob: Equatable {
    case cleanPreview, cleanRun, optimizePreview

    var arguments: [String] {
        switch self {
        case .cleanPreview: return ["clean", "--dry-run"]
        case .cleanRun: return ["clean"]
        case .optimizePreview: return ["optimize", "--dry-run"]
        }
    }

    var title: String {
        switch self {
        case .cleanPreview: return "Temizlik önizlemesi"
        case .cleanRun: return "Temizlik"
        case .optimizePreview: return "Bakım önizlemesi"
        }
    }

    var timeoutSeconds: Double { self == .optimizePreview ? 120 : 300 }
}

/// Mole çıktısını canlı okur. Çıktı biçimi: "➤ Bölüm", "→ Öğe, 2.92GB dry",
/// "Potential space: 9.40GB | Items: 317 | Categories: 32". Biçim değişirse satırlar atlanır.
@MainActor
final class CleanPreview: ObservableObject {
    enum Phase { case idle, running, done, failed }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var job: MoleJob = .cleanPreview
    @Published private(set) var lines: [PreviewLine] = []
    @Published private(set) var rawTail: [String] = []
    @Published private(set) var summary: String?
    @Published private(set) var currentSection = ""
    @Published private(set) var startedAt = Date()
    @Published private(set) var freedBytes: Int64?
    @Published var confirming = false

    private var process: Process?
    private var buffer = ""
    private var cancelled = false
    private var nextID = 0
    private var freeBefore: UInt64 = 0
    private var backgroundRun = false

    private static let sizePattern = try? NSRegularExpression(
        pattern: #"^(.*?),?\s+(\d+(?:\.\d+)?\s?(?:B|KB|MB|GB|TB))(?:\s+dry)?$"#
    )

    /// Haftalık otomatik tarama (yalnızca önizleme). Ayar açıksa, 7 günden eskiyse ve düşük güç modunda değilse çalışır.
    func startIfDue() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "weeklyScan"), phase != .running,
              !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        let last = defaults.object(forKey: "lastScheduledScan") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 7 * 24 * 3600 else { return }
        defaults.set(Date(), forKey: "lastScheduledScan")
        start(.cleanPreview, background: true)
    }

    func start(_ job: MoleJob, background: Bool = false) {
        guard phase != .running else { return }
        self.job = job
        backgroundRun = background
        confirming = false
        guard MoleCLI.isInstalled else { phase = .failed; return }
        lines = []
        rawTail = []
        summary = nil
        currentSection = ""
        buffer = ""
        cancelled = false
        nextID = 0
        freedBytes = nil
        freeBefore = sampleDisk().freeBytes
        startedAt = Date()

        let task = Process()
        task.executableURL = URL(fileURLWithPath: MoleCLI.path)
        task.arguments = job.arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        task.environment = environment
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.standardInput = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                Task { @MainActor in self?.finish() }
                return
            }
            let chunk = String(decoding: data, as: UTF8.self)
            Task { @MainActor in self?.consume(chunk) }
        }

        do {
            try task.run()
        } catch {
            phase = .failed
            return
        }
        process = task
        phase = .running

        DispatchQueue.global().asyncAfter(deadline: .now() + job.timeoutSeconds) {
            if task.isRunning { task.terminate() }
        }
    }

    func cancel() {
        cancelled = true
        process?.terminate()
    }

    private func consume(_ chunk: String) {
        buffer += chunk
        var parts = buffer.replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        buffer = parts.removeLast()
        for raw in parts { handle(Self.clean(raw)) }
    }

    private func finish() {
        guard phase == .running else { return }
        if !buffer.isEmpty { handle(Self.clean(buffer)); buffer = "" }
        process = nil
        if cancelled {
            phase = .idle
            lines = []
            summary = nil
        } else if job == .cleanRun {
            // Silme işleminde çıktı tanınmasa da sonuç gösterilir; kazanım diskten ölçülür.
            let freeAfter = sampleDisk().freeBytes
            freedBytes = Int64(freeAfter) - Int64(freeBefore)
            phase = .done
        } else {
            phase = (summary != nil || !lines.isEmpty) ? .done : .failed
            if backgroundRun, phase == .done, let summary {
                let value = summary.components(separatedBy: "|").first?
                    .split(separator: ":", maxSplits: 1).last?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                Task {
                    let cache = await Task.detached { CacheCleaner.totalCacheBytes() }.value
                    ReclaimStore.save(.cache, bytes: cache)
                    FolderLog.record(["Önbellek": cache])
                    let growth = FolderGrowth.summaryLine(FolderGrowth.compute(Array(FolderLog.load().suffix(30))))
                    DiskNotifier.post(
                        title: "Haftalık tarama bitti",
                        body: "Temizlenebilir alan: \(value). Önbellek: \(formatBytes(cache)). "
                            + (growth.map { $0 + " " } ?? "")
                            + "Araçlar sekmesinden inceleyin. Hiçbir şey silinmedi.",
                        id: "molebar.scan"
                    )
                    let limitGB = UserDefaults.standard.integer(forKey: "cacheAlertGB")
                    if limitGB > 0, cache >= UInt64(limitGB) * 1_000_000_000 {
                        DiskNotifier.post(
                            title: "Önbellek eşiği aşıldı",
                            body: "Önbellek \(formatBytes(cache)). Eşik \(limitGB) GB. Önbellek sekmesinden inceleyin.",
                            id: "molebar.cache"
                        )
                    }
                }
            }
        }
        backgroundRun = false
    }

    private func handle(_ line: String) {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard let first = text.first else { return }
        rawTail.append(text)
        if rawTail.count > 14 { rawTail.removeFirst() }
        if text.contains("Potential space:") { summary = text; return }
        let body = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        switch first {
        case "➤":
            currentSection = body
            append(.section, body)
        case "→":
            let (name, size) = Self.splitSize(body)
            append(.item, name, size: size)
        case "✓":
            append(.ok, body)
        case "◎", "☞":
            append(.note, body)
        default:
            break
        }
    }

    private func append(_ kind: PreviewLine.Kind, _ text: String, size: String? = nil) {
        lines.append(PreviewLine(id: nextID, kind: kind, text: text, size: size))
        nextID += 1
    }

    private static func splitSize(_ text: String) -> (String, String?) {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = sizePattern?.firstMatch(in: text, range: range),
              let nameRange = Range(match.range(at: 1), in: text),
              let sizeRange = Range(match.range(at: 2), in: text) else { return (text, nil) }
        return (String(text[nameRange]), String(text[sizeRange]))
    }

    private static func clean(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[a-zA-Z]", with: "", options: .regularExpression)
    }
}

struct CleanPreviewPage: View {
    @ObservedObject var preview: CleanPreview

    var body: some View {
        ScrollView(showsIndicators: false) {
            GlassGroup(spacing: 12) {
                VStack(spacing: 14) {
                    statusCard
                    if preview.job == .cleanRun && preview.phase == .done && !preview.rawTail.isEmpty { tailCard }
                    if !preview.lines.isEmpty && preview.job != .cleanRun { listCard }
                }
            }
        }
    }

    // MARK: Durum kartı

    @ViewBuilder
    private var statusCard: some View {
        switch preview.phase {
        case .running: runningCard
        case .done: doneCard
        case .failed: failedCard
        case .idle: idleCard
        }
    }

    private var runningCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(preview.job == .cleanRun ? "Temizleniyor" : "Taranıyor")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(preview.startedAt, style: .timer)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(preview.currentSection.isEmpty ? "Başlıyor…" : preview.currentSection)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(preview.job == .cleanRun
                 ? "Dosyalar siliniyor. İptal edilen işlem yarım kalabilir."
                 : "Hiçbir şey silinmez. Tarama 10 saniye ile 2 dakika sürer.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("İptal") { preview.cancel() }
                .glassButton()
                .controlSize(.small)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: preview.job == .cleanRun ? .orange : nil)
    }

    @ViewBuilder
    private var doneCard: some View {
        switch preview.job {
        case .cleanPreview: cleanPreviewDoneCard
        case .cleanRun: cleanRunDoneCard
        case .optimizePreview: optimizeDoneCard
        }
    }

    private var cleanPreviewDoneCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if preview.summary != nil {
                Text(summaryParts.first?.value ?? "")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text(summaryParts.first?.label ?? "Temizlenebilir alan")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(Array(summaryParts.dropFirst().enumerated()), id: \.offset) { _, part in
                        Text("\(part.label): \(part.value)")
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.primary.opacity(0.08), in: Capsule())
                    }
                }
            } else {
                Text("Tarama tamamlanmadı").font(.subheadline.weight(.semibold))
                Text("Özet satırı alınamadı. Liste kısmi olabilir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Önizleme. Hiçbir şey silinmedi. Sistem önbellekleri (sudo gerektirir) dahil değildir.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if preview.confirming {
                confirmBox
            } else {
                HStack(spacing: 8) {
                    if preview.summary != nil {
                        Button("Temizle…") { preview.confirming = true }
                            .glassButton()
                            .controlSize(.small)
                    }
                    Button("Yeniden tara") { preview.start(.cleanPreview) }
                        .glassButton()
                        .controlSize(.small)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: .green)
    }

    private var confirmBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Silme işlemi geri alınamaz", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Text("Önizlemedeki kullanıcı önbellekleri, loglar ve geçici dosyalar silinir. Sistem önbellekleri atlanır. Önizleme ile gerçek sonuç küçük farklar gösterebilir.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Evet, temizle") { preview.start(.cleanRun) }
                    .glassButton()
                    .controlSize(.small)
                Button("Vazgeç") { preview.confirming = false }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var cleanRunDoneCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Temizlik bitti").font(.subheadline.weight(.semibold))
            if let freed = preview.freedBytes {
                Text(freed > 0 ? "Boşalan alan: \(formatBytes(UInt64(freed)))" : "Ölçülen fark: yok")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Disk boş alanından ölçüldü. Sistem, arka planda silinenleri geç yansıtabilir.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Yeni tarama") { preview.start(.cleanPreview) }
                .glassButton()
                .controlSize(.small)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: .green)
    }

    private var optimizeDoneCard: some View {
        let steps = preview.lines.filter { $0.kind == .item }.count
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(steps) bakım adımı").font(.system(size: 26, weight: .semibold, design: .rounded))
            Text("Önizleme. Hiçbir şey değişmedi.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Gerçek çalıştırma yönetici izni ister. DNS, Dock ve Bluetooth kısa süre yeniden başlayabilir. Bu yüzden Terminal'de çalışır.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Terminal'de çalıştır") { TerminalBridge.run("mo optimize") }
                    .glassButton()
                    .controlSize(.small)
                Button("Yeniden tara") { preview.start(.optimizePreview) }
                    .glassButton()
                    .controlSize(.small)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: .blue)
    }

    private var failedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("İşlem alınamadı").font(.subheadline.weight(.semibold))
            Text(MoleCLI.isInstalled
                 ? "Mole çıktısı tanınmadı veya işlem başarısız oldu."
                 : "Mole kurulu değil: \(MoleCLI.path)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Yeniden dene") { preview.start(preview.job) }
                .glassButton()
                .controlSize(.small)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: .red)
    }

    private var idleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(preview.job.title).font(.subheadline.weight(.semibold))
            Text("Mole tarar. Önizlemede hiçbir şey silinmez.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Taramayı başlat") { preview.start(preview.job) }
                .glassButton()
                .controlSize(.small)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var summaryParts: [(label: String, value: String)] {
        guard let summary = preview.summary else { return [] }
        return summary.components(separatedBy: "|").compactMap { part in
            let pieces = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pieces.count == 2 else { return nil }
            return (label: Self.translate(pieces[0]), value: pieces[1])
        }
    }

    private static func translate(_ label: String) -> String {
        switch label {
        case "Potential space": return "Temizlenebilir alan (tahmini)"
        case "Items": return "Öğe"
        case "Categories": return "Kategori"
        default: return label
        }
    }

    // MARK: Liste

    private var sections: [(title: String, rows: [PreviewLine])] {
        var result: [(title: String, rows: [PreviewLine])] = []
        for line in preview.lines {
            if line.kind == .section {
                result.append((title: line.text, rows: []))
            } else if !result.isEmpty {
                result[result.count - 1].rows.append(line)
            }
        }
        return result
    }

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(symbol: "list.bullet", title: "Ayrıntı (Mole çıktısı)")
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(section.rows) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: symbol(for: row.kind))
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                                .frame(width: 10)
                            Text(row.text)
                                .font(.caption)
                                .lineLimit(2)
                                .foregroundStyle(row.kind == .item ? .primary : .secondary)
                            Spacer(minLength: 4)
                            if let size = row.size {
                                Text(size)
                                    .font(.caption.weight(.medium).monospacedDigit())
                                    .fixedSize()
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// Gerçek temizlik çıktısı biçimi doğrulanmadı. Son satırlar ham gösterilir.
    private var tailCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(symbol: "text.alignleft", title: "Mole çıktısının sonu")
            ForEach(Array(preview.rawTail.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func symbol(for kind: PreviewLine.Kind) -> String {
        switch kind {
        case .item: return "circle.fill"
        case .ok: return "checkmark"
        case .note: return "info.circle"
        case .section: return "circle"
        }
    }
}
