import AppKit
import SwiftUI

struct DiskEntry: Identifiable {
    let url: URL
    let isDirectory: Bool
    var bytes: UInt64 = 0
    var items = 0
    var sized = false
    var isPackage = false
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

struct DiskMeasure {
    let url: URL
    let bytes: UInt64
    let items: Int
    let errors: Int
}

/// Seçilen klasörün alt öğelerini boyutlarıyla listeler. Yalnızca okur, hiçbir şeyi silmez veya değiştirmez.
/// Sembolik bağlantılar izlenmez. Bağlı birim sınırları aşılmaz (harici diskler ve APFS çift sayımı karışmaz).
@MainActor
final class DiskAnalyzer: ObservableObject {
    @Published private(set) var current = FileManager.default.homeDirectoryForCurrentUser
    @Published private(set) var entries: [DiskEntry] = []
    @Published private(set) var isScanning = false
    @Published private(set) var pending = 0
    @Published private(set) var inaccessible = 0
    @Published private(set) var listError: String?
    @Published var pendingTrash: URL?
    @Published var notice: String?

    private var stack: [URL] = []
    private var task: Task<Void, Never>?
    private var started = false

    var canGoBack: Bool { !stack.isEmpty }
    var totalBytes: UInt64 { entries.reduce(0) { $0 + $1.bytes } }
    var largestBytes: UInt64 { entries.map(\.bytes).max() ?? 0 }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        scan(current)
    }

    func jump(to url: URL) {
        stack = []
        scan(url)
    }

    func open(_ entry: DiskEntry) {
        guard entry.isDirectory else { return }
        stack.append(current)
        scan(entry.url)
    }

    func goBack() {
        guard let previous = stack.popLast() else { return }
        scan(previous)
    }

    func rescan() { scan(current) }

    /// Geçerli klasörün listesini CSV dosyasına yazar. Yol kullanıcının seçtiği kaydetme penceresinden gelir.
    func exportCSV() {
        let rows = entries.map { [$0.name, $0.isDirectory ? L("Klasör") : L("Dosya"), String($0.bytes), String($0.items)] }
        let text = CSVExport.make(header: [L("Ad"), L("Tür"), L("Boyut (bayt)"), L("Öğe sayısı")], rows: rows)
        let folder = current.lastPathComponent.isEmpty ? "disk" : current.lastPathComponent
        if let name = CSVExport.save(text, suggestedName: "analiz-\(folder).csv") {
            notice = L("%ld satır %@ dosyasına kaydedildi.", entries.count, name)
        }
    }

    /// Öğeyi Çöp Kutusu'na taşır. Geri alınabilir. Başarılıysa listeden çıkarır.
    func moveToTrash(_ entry: DiskEntry) throws {
        guard TrashGuard.canTrash(entry.url) else { throw CocoaError(.fileWriteNoPermission) }
        try TrashGuard.trash(entry.url, bytes: entry.bytes, source: "Analiz")
        entries.removeAll { $0.url == entry.url }
    }

    func cancel() {
        task?.cancel()
        isScanning = false
    }

    private func scan(_ url: URL) {
        task?.cancel()
        current = url
        entries = []
        listError = nil
        inaccessible = 0
        started = true

        let children: [DiskEntry]
        do {
            children = try Self.children(of: url)
        } catch {
            listError = L("Klasör okunamadı. Tam Disk Erişimi gerekebilir.")
            isScanning = false
            pending = 0
            return
        }
        entries = children
        pending = children.count
        isScanning = !children.isEmpty

        task = Task { [weak self] in
            await withTaskGroup(of: DiskMeasure.self) { group in
                for child in children {
                    group.addTask { Self.measure(child) }
                }
                for await result in group {
                    if Task.isCancelled { break }
                    self?.apply(result)
                }
            }
            if !Task.isCancelled { self?.isScanning = false }
        }
    }

    private func apply(_ result: DiskMeasure) {
        guard entries.contains(where: { $0.url == result.url }) else { return }
        entries = Self.applying(result, to: entries)
        pending = max(pending - 1, 0)
        inaccessible += result.errors
    }

    /// Ölçümü ilgili satıra yazar ve listeyi büyükten küçüğe sıralar. Listede olmayan ölçüm yok sayılır.
    nonisolated static func applying(_ result: DiskMeasure, to entries: [DiskEntry]) -> [DiskEntry] {
        guard entries.contains(where: { $0.url == result.url }) else { return entries }
        return entries
            .map { entry in
                guard entry.url == result.url else { return entry }
                var updated = entry
                updated.bytes = result.bytes
                updated.items = result.items
                updated.sized = true
                return updated
            }
            .sorted { $0.bytes > $1.bytes }
    }

    nonisolated static func children(of url: URL) throws -> [DiskEntry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [])
        return urls.map { child in
            let values = try? child.resourceValues(forKeys: Set(keys))
            let isLink = values?.isSymbolicLink ?? false
            let isPackage = !isLink && (values?.isPackage ?? false)
            var entry = DiskEntry(url: child, isDirectory: !isLink && !isPackage && (values?.isDirectory ?? false))
            entry.isPackage = isPackage
            return entry
        }
    }

    nonisolated static func measure(_ entry: DiskEntry) -> DiskMeasure {
        let sizeKeys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isDirectoryKey, .isVolumeKey]
        if !entry.isDirectory && !entry.isPackage {
            let size = (try? entry.url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0
            return DiskMeasure(url: entry.url, bytes: UInt64(size), items: 1, errors: 0)
        }

        var bytes: UInt64 = 0
        var items = 0
        var errors = 0
        guard let enumerator = FileManager.default.enumerator(
            at: entry.url,
            includingPropertiesForKeys: sizeKeys,
            options: [],
            errorHandler: { _, _ in errors += 1; return true }
        ) else { return DiskMeasure(url: entry.url, bytes: 0, items: 0, errors: 1) }

        for case let fileURL as URL in enumerator {
            if Task.isCancelled { break }
            let values = try? fileURL.resourceValues(forKeys: Set(sizeKeys))
            if values?.isDirectory == true {
                if values?.isVolume == true { enumerator.skipDescendants() }
                continue
            }
            bytes += UInt64(values?.totalFileAllocatedSize ?? 0)
            items += 1
        }
        return DiskMeasure(url: entry.url, bytes: bytes, items: items, errors: errors)
    }
}

struct AnalyzePage: View {
    @ObservedObject var analyzer: DiskAnalyzer
    let volumes: [VolumeInfo]
    @AppStorage("analyzeView") private var viewMode = "list"

    private var shortcuts: [(title: String, url: URL)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var result: [(title: String, url: URL)] = [
            (title: L("Ev"), url: home),
            (title: L("İndirilenler"), url: home.appendingPathComponent("Downloads")),
            (title: L("Masaüstü"), url: home.appendingPathComponent("Desktop")),
            (title: L("Kütüphane"), url: home.appendingPathComponent("Library")),
            (title: L("Uygulamalar"), url: URL(fileURLWithPath: "/Applications"))
        ]
        for volume in volumes where !volume.isInternal {
            result.append((title: volume.name, url: URL(fileURLWithPath: volume.path)))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Disk analizi").font(.title2.weight(.semibold))
                Spacer()
                Picker("Görünüm", selection: $viewMode) {
                    Text("Liste").tag("list")
                    Text("Harita").tag("map")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
            }
            shortcutRow
            pathBar
            if viewMode == "map" {
                mapContent
            } else {
                listScroll
            }
            if let notice = analyzer.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
            Text("Tarama salt okunurdur. Çöp ikonu öğeyi Çöp Kutusu'na taşır; kalıcı silmez. Ev klasörünün doğrudan alt öğeleri korunur. Harici diskler kendi kısayolundan taranır.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .onAppear { analyzer.startIfNeeded() }
    }

    /// Harita: karo alanı boyutla orantılıdır. Küçük karolar etiketsiz kalır, üzerine gelince ad ve boyut görünür.
    @ViewBuilder
    private var mapContent: some View {
        if let error = analyzer.listError {
            Text(error).font(.caption).foregroundStyle(.secondary)
        } else if analyzer.entries.isEmpty && !analyzer.isScanning {
            Text("Klasör boş.").font(.caption).foregroundStyle(.secondary)
        } else {
            TreemapView(entries: analyzer.entries) { analyzer.open($0) }
                .frame(maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
                .padding(8)
                .glassCard()
            if analyzer.inaccessible > 0 {
                Text(FullDiskAccess.inaccessibleNote(analyzer.inaccessible))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var listScroll: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                GlassGroup(spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) { listContent }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()
                }
            }
            .shadowSafeScroll()
        }
    }

    private var shortcutRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { _, shortcut in
                    Button(shortcut.title) { analyzer.jump(to: shortcut.url) }
                        .glassButton()
                        .controlSize(.small)
                }
            }
        }
    }

    private var pathBar: some View {
        HStack(spacing: 8) {
            Button { analyzer.goBack() } label: { Image(systemName: "chevron.left") }
                .glassButton()
                .disabled(!analyzer.canGoBack)
                .help("Geri")
                .accessibilityLabel("Geri")
            VStack(alignment: .leading, spacing: 0) {
                Text(analyzer.current.lastPathComponent.isEmpty ? "/" : analyzer.current.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Text(analyzer.current.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 8)
            if analyzer.isScanning {
                ProgressView().controlSize(.small)
                Text(L("%ld kaldı", analyzer.pending))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Durdur") { analyzer.cancel() }
                    .glassButton()
                    .controlSize(.small)
            } else {
                Text(formatBytes(analyzer.totalBytes))
                    .font(.headline.monospacedDigit())
            }
            Button { analyzer.rescan() } label: { Image(systemName: "arrow.clockwise") }
                .glassButton()
                .help("Yeniden tara")
                .accessibilityLabel("Yeniden tara")
            Button { analyzer.exportCSV() } label: { Image(systemName: "square.and.arrow.up") }
                .glassButton()
                .disabled(analyzer.entries.isEmpty || analyzer.isScanning)
                .help("Bu klasörün listesini CSV olarak kaydet")
                .accessibilityLabel("Bu klasörün listesini CSV olarak kaydet")
            Button { NSWorkspace.shared.open(analyzer.current) } label: { Image(systemName: "folder") }
                .glassButton()
                .help("Finder'da aç")
                .accessibilityLabel("Finder'da aç")
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if let error = analyzer.listError {
            Text(error).font(.caption).foregroundStyle(.secondary)
        } else if analyzer.entries.isEmpty && !analyzer.isScanning {
            Text("Klasör boş.").font(.caption).foregroundStyle(.secondary)
        } else {
            ForEach(analyzer.entries) { entry in
                row(entry)
                Divider().opacity(0.4)
            }
            if analyzer.inaccessible > 0 {
                Text(FullDiskAccess.inaccessibleNote(analyzer.inaccessible))
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.top, 8)
            }
        }
    }

    private func trash(_ entry: DiskEntry) {
        analyzer.pendingTrash = nil
        do {
            try analyzer.moveToTrash(entry)
            analyzer.notice = L("%@ Çöp Kutusu'na taşındı. Finder'dan geri alınabilir.", entry.name)
        } catch {
            analyzer.notice = L("%@ taşınamadı: %@", entry.name, error.localizedDescription)
        }
    }

    private func row(_ entry: DiskEntry) -> some View {
        let share = analyzer.largestBytes == 0 ? 0 : Double(entry.bytes) / Double(analyzer.largestBytes) * 100
        return HStack(spacing: 10) {
            Image(systemName: entry.isPackage ? "shippingbox" : (entry.isDirectory ? "folder.fill" : "doc"))
                .foregroundStyle(entry.isDirectory ? Color.accentColor : Color.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.name).font(.subheadline).lineLimit(1).truncationMode(.middle)
                    if entry.isDirectory && entry.sized {
                        Text(L("%ld öğe", entry.items)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                UsageBar(percent: entry.sized ? share : 0, height: 4, color: .accentColor)
            }
            Spacer(minLength: 8)
            if entry.sized {
                Text(formatBytes(entry.bytes))
                    .font(.subheadline.weight(.medium).monospacedDigit())
            } else {
                ProgressView().controlSize(.mini)
            }
            if analyzer.pendingTrash == entry.url {
                Button("Çöp Kutusu'na taşı") { trash(entry) }
                    .glassButton()
                    .controlSize(.small)
                    .fixedSize()
                Button("Vazgeç") { analyzer.pendingTrash = nil }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            } else {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                } label: { Image(systemName: "magnifyingglass.circle") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Finder'da göster")
                    .accessibilityLabel("Finder'da göster")
                let allowed = TrashGuard.canTrash(entry.url)
                Button { analyzer.pendingTrash = entry.url } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                    .foregroundStyle(allowed ? Color.secondary : Color.secondary.opacity(0.3))
                    .disabled(!allowed)
                    .help(L(allowed ? "Çöp Kutusu'na taşı" : "Bu öğe korumalı"))
            }
            if entry.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { analyzer.open(entry) }
    }
}
