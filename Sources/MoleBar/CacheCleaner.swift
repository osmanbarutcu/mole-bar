import AppKit
import SwiftUI

enum CacheCategory: String, CaseIterable {
    case app = "Uygulama önbelleği"
    case logs = "Günlükler"
    case dev = "Geliştirici önbelleği"
}

struct CacheItem: Identifiable {
    let url: URL
    let category: CacheCategory
    let bytes: UInt64
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

/// Yeniden üretilebilen kullanıcı önbelleklerini listeler. Tarama salt okunurdur.
/// Seçilenler Çöp Kutusu'na taşınır (geri alınabilir). Çöp Kutusu'nu boşaltmak kalıcıdır ve ayrı onay ister.
/// Apple sistem önbellekleri (com.apple.*) ve MoleBar kendisi listelenmez.
@MainActor
final class CacheCleaner: ObservableObject {
    @Published private(set) var items: [CacheItem] = []
    @Published private(set) var isScanning = false
    @Published private(set) var trashBytes: UInt64 = 0
    @Published var selection = Set<URL>()
    @Published var confirmingMove = false
    @Published var confirmingEmpty = false
    @Published var notice: String?

    private var task: Task<Void, Never>?
    private var started = false

    var selectedBytes: UInt64 { items.filter { selection.contains($0.url) }.reduce(0) { $0 + $1.bytes } }

    func items(in category: CacheCategory) -> [CacheItem] { items.filter { $0.category == category } }

    func scanIfNeeded() {
        guard !started else { return }
        scan()
    }

    func scan() {
        started = true
        task?.cancel()
        items = []
        selection = []
        confirmingMove = false
        isScanning = true
        task = Task { [weak self] in
            let trash = await Task.detached { Self.trashSize() }.value
            self?.trashBytes = trash
            for await item in Self.stream() {
                if Task.isCancelled { break }
                guard let self else { return }
                self.items.append(item)
                self.items.sort { $0.bytes > $1.bytes }
            }
            self?.isScanning = false
            if !Task.isCancelled { self?.persist() }
        }
    }

    /// Kazanılabilir alan kartı için son sonucu yazar.
    private func persist() {
        ReclaimStore.save(.cache, bytes: items.reduce(0) { $0 + $1.bytes })
        ReclaimStore.save(.trash, bytes: trashBytes)
    }

    func toggle(_ item: CacheItem) {
        if selection.contains(item.url) { selection.remove(item.url) } else { selection.insert(item.url) }
        confirmingMove = false
    }

    func selectAll(in category: CacheCategory) {
        let urls = items(in: category).map(\.url)
        if urls.allSatisfy({ selection.contains($0) }) { selection.subtract(urls) } else { selection.formUnion(urls) }
        confirmingMove = false
    }

    /// Seçilenleri Çöp Kutusu'na taşır. Geri alınabilir.
    func moveSelectedToTrash() {
        confirmingMove = false
        var moved: UInt64 = 0
        var failed = 0
        for item in items where selection.contains(item.url) {
            guard DiskAnalyzer.canTrash(item.url) else { failed += 1; continue }
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                moved += item.bytes
            } catch { failed += 1 }
        }
        let chosen = selection
        items.removeAll { chosen.contains($0.url) && !FileManager.default.fileExists(atPath: $0.url.path) }
        selection = []
        trashBytes += moved
        persist()
        notice = failed == 0
            ? "\(formatBytes(moved)) Çöp Kutusu'na taşındı. Alan, Çöp Kutusu boşalınca açılır."
            : "\(formatBytes(moved)) taşındı. \(failed) öğe taşınamadı."
    }

    /// Finder ile Çöp Kutusu'nu boşaltır. KALICIDIR.
    func emptyTrash() {
        confirmingEmpty = false
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&error)
        if let error {
            notice = "Çöp Kutusu boşaltılamadı: \(error[NSAppleScript.errorMessage] as? String ?? "bilinmeyen hata")"
        } else {
            trashBytes = 0
            persist()
            notice = "Çöp Kutusu boşaltıldı."
        }
    }

    // MARK: Tarama

    private nonisolated static func trashSize() -> UInt64 {
        AppUninstaller.size(of: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
    }

    private nonisolated static func stream() -> AsyncStream<CacheItem> {
        AsyncStream { continuation in
            let worker = Task.detached {
                for (url, category) in candidates() {
                    if Task.isCancelled { break }
                    let bytes = AppUninstaller.size(of: url)
                    if bytes > 0 { continuation.yield(CacheItem(url: url, category: category, bytes: bytes)) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    private nonisolated static func candidates() -> [(URL, CacheCategory)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        func children(_ relative: String, _ category: CacheCategory, skipApple: Bool = false) -> [(URL, CacheCategory)] {
            let dir = home.appendingPathComponent(relative)
            let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            return urls
                .filter { !(skipApple && $0.lastPathComponent.hasPrefix("com.apple.")) && $0.lastPathComponent != "local.molebar" }
                .map { ($0, category) }
        }
        func single(_ relative: String, _ category: CacheCategory) -> [(URL, CacheCategory)] {
            let url = home.appendingPathComponent(relative)
            return FileManager.default.fileExists(atPath: url.path) ? [(url, category)] : []
        }
        return children("Library/Caches", .app, skipApple: true)
            + children("Library/Logs", .logs)
            + children(".cache", .dev)
            + children("Library/Developer/Xcode/DerivedData", .dev)
            + single(".npm/_cacache", .dev)
            + single(".gradle/caches", .dev)
    }
}

struct CachePage: View {
    @ObservedObject var cleaner: CacheCleaner

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Önbellek ve Çöp Kutusu").font(.title2.weight(.semibold))
                Spacer()
                if cleaner.isScanning { ProgressView().controlSize(.small) }
                Button { cleaner.scan() } label: { Image(systemName: "arrow.clockwise") }
                    .glassButton()
                    .disabled(cleaner.isScanning)
                    .help("Yeniden tara")
            }
            trashCard
            if let notice = cleaner.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                GlassGroup(spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(CacheCategory.allCases, id: \.self) { category in
                            let rows = cleaner.items(in: category)
                            if !rows.isEmpty { section(category, rows) }
                        }
                        if cleaner.items.isEmpty {
                            Text(cleaner.isScanning ? "Taranıyor..." : "Listelenecek önbellek bulunamadı.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .glassCard()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .shadowSafeScroll()
            footer
        }
        .padding(20)
        .onAppear { cleaner.scanIfNeeded() }
    }

    private var trashCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text("Çöp Kutusu").font(.subheadline.weight(.semibold))
                Text(formatBytes(cleaner.trashBytes)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            if cleaner.confirmingEmpty {
                Text("Kalıcı silinir, geri alınamaz.").font(.caption).foregroundStyle(.red)
                Button("Boşalt") { cleaner.emptyTrash() }.glassProminentButton()
                Button("Vazgeç") { cleaner.confirmingEmpty = false }.glassButton()
            } else {
                Button("Çöp Kutusu'nu boşalt") { cleaner.confirmingEmpty = true }
                    .glassButton()
                    .disabled(cleaner.trashBytes == 0)
            }
        }
        .padding(12)
        .glassCard()
    }

    private func section(_ category: CacheCategory, _ rows: [CacheItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                CardHeader(symbol: "internaldrive", title: category.rawValue, trailing: formatBytes(rows.reduce(0) { $0 + $1.bytes }))
                Button(rows.allSatisfy({ cleaner.selection.contains($0.url) }) ? "Seçimi kaldır" : "Hepsini seç") {
                    cleaner.selectAll(in: category)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            }
            ForEach(rows) { item in
                HStack(spacing: 8) {
                    Image(systemName: cleaner.selection.contains(item.url) ? "checkmark.square.fill" : "square")
                        .foregroundStyle(cleaner.selection.contains(item.url) ? Color.accentColor : Color.secondary)
                    Text(item.name).font(.subheadline).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(formatBytes(item.bytes)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { cleaner.toggle(item) }
            }
        }
        .padding(12)
        .glassCard()
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 10) {
            Text(cleaner.selection.isEmpty ? "Öğe seçin." : "\(cleaner.selection.count) öğe · \(formatBytes(cleaner.selectedBytes))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            if cleaner.confirmingMove {
                Text("Çöp Kutusu'na taşınacak.").font(.caption)
                Button("Taşı") { cleaner.moveSelectedToTrash() }.glassProminentButton()
                Button("Vazgeç") { cleaner.confirmingMove = false }.glassButton()
            } else {
                Button { cleaner.confirmingMove = true } label: { Label("Çöp Kutusu'na taşı", systemImage: "trash") }
                    .glassButton()
                    .disabled(cleaner.selection.isEmpty)
            }
        }
        Text("Önbellekler uygulamalar tarafından yeniden üretilir. Taşıma geri alınabilir ama alan yalnızca Çöp Kutusu boşalınca açılır. Apple sistem önbellekleri listelenmez.")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
