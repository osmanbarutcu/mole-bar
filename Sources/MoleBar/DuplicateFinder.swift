import AppKit
import CryptoKit
import SwiftUI

struct DuplicateGroup: Identifiable {
    let id: String
    let size: UInt64
    var files: [URL]
    var wasted: UInt64 { size * UInt64(max(files.count - 1, 0)) }
}

/// Ev klasöründe aynı içeriğe sahip dosyaları bulur. Tarama salt okunurdur.
/// Gizli klasörler, ~/Library ve paket (.app) içleri atlanır. Önce boyut, sonra ilk 64 KB özeti, en son tam SHA-256 karşılaştırılır.
@MainActor
final class DuplicateFinder: ObservableObject {
    static let minSizes: [(label: String, bytes: UInt64)] = [
        ("1 MB", 1 << 20), ("10 MB", 10 << 20), ("100 MB", 100 << 20)
    ]

    @Published private(set) var groups: [DuplicateGroup] = []
    @Published private(set) var isScanning = false
    @Published private(set) var phase = ""
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    @Published private(set) var inaccessible = 0
    @Published private(set) var finished = false
    @Published var minSizeIndex = 1
    @Published var pendingTrash: URL?
    @Published var notice: String?

    private var task: Task<Void, Never>?
    private let maxGroups = 150

    var totalWasted: UInt64 { groups.reduce(0) { $0 + $1.wasted } }

    func scan() {
        task?.cancel()
        groups = []
        done = 0
        total = 0
        inaccessible = 0
        finished = false
        pendingTrash = nil
        isScanning = true
        let minSize = Self.minSizes[minSizeIndex].bytes
        let cap = maxGroups
        task = Task { [weak self] in
            for await event in Self.stream(minSize: minSize) {
                if Task.isCancelled { break }
                guard let self else { return }
                switch event {
                case .progress(let phase, let done, let total, let errors):
                    self.phase = phase
                    self.done = done
                    self.total = total
                    self.inaccessible = errors
                case .group(let group):
                    self.groups.append(group)
                    self.groups.sort { $0.wasted > $1.wasted }
                    if self.groups.count > cap { self.groups.removeLast() }
                }
            }
            guard let self else { return }
            self.isScanning = false
            self.finished = !Task.isCancelled
        }
    }

    func cancel() {
        task?.cancel()
        isScanning = false
    }

    /// Bir kopyayı Çöp Kutusu'na taşır. Gruptaki son kopya taşınamaz.
    func moveToTrash(_ url: URL, from groupID: String) {
        pendingTrash = nil
        guard let index = groups.firstIndex(where: { $0.id == groupID }), groups[index].files.count > 1 else { return }
        guard DiskAnalyzer.canTrash(url) else {
            notice = "\(url.lastPathComponent) korumalı bir yolda. Finder'da gösterin."
            return
        }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            groups[index].files.removeAll { $0 == url }
            if groups[index].files.count < 2 { groups.remove(at: index) }
            notice = "\(url.lastPathComponent) Çöp Kutusu'na taşındı. Finder'dan geri alınabilir."
        } catch {
            notice = "\(url.lastPathComponent) taşınamadı: \(error.localizedDescription)"
        }
    }

    // MARK: Tarama

    private enum Event {
        case progress(String, Int, Int, Int)
        case group(DuplicateGroup)
    }

    private nonisolated static func stream(minSize: UInt64) -> AsyncStream<Event> {
        AsyncStream { continuation in
            let worker = Task.detached {
                run(minSize: minSize) { continuation.yield($0) }
                continuation.finish()
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    /// Senkron iş akışı. Async bağlamda NSEnumerator kullanılmaz.
    private nonisolated static func run(minSize: UInt64, emit: (Event) -> Void) {
        var errors = 0
        let bySize = collect(minSize: minSize, errors: &errors, emit: emit)
        let candidates = bySize.filter { $0.value.count > 1 }
        let total = candidates.values.reduce(0) { $0 + $1.count }
        var done = 0
        emit(.progress("Özet hesaplanıyor", 0, total, errors))

        for (size, urls) in candidates.sorted(by: { $0.key > $1.key }) {
            if Task.isCancelled { return }
            var byPartial: [String: [URL]] = [:]
            for url in urls {
                if let key = digest(of: url, limit: 64 << 10) { byPartial[key, default: []].append(url) }
                else { errors += 1 }
            }
            for sameStart in byPartial.values where sameStart.count > 1 {
                var byFull: [String: [URL]] = [:]
                for url in sameStart {
                    if Task.isCancelled { return }
                    if let key = digest(of: url, limit: nil) { byFull[key, default: []].append(url) }
                    else { errors += 1 }
                }
                for (key, same) in byFull where same.count > 1 {
                    emit(.group(DuplicateGroup(id: key, size: size, files: same.sorted { $0.path < $1.path })))
                }
            }
            done += urls.count
            emit(.progress("Özet hesaplanıyor", done, total, errors))
        }
    }

    private nonisolated static func collect(minSize: UInt64, errors: inout Int, emit: (Event) -> Void) -> [UInt64: [URL]] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isVolumeKey, .fileSizeKey]
        let home = FileManager.default.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library").path
        var failed = 0
        guard let enumerator = FileManager.default.enumerator(
            at: home,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants, .skipsHiddenFiles],
            errorHandler: { _, _ in failed += 1; return true }
        ) else { return [:] }

        var bySize: [UInt64: [URL]] = [:]
        var count = 0
        for case let url as URL in enumerator {
            if Task.isCancelled { break }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if url.path == library || values?.isVolume == true { enumerator.skipDescendants() }
                continue
            }
            guard values?.isRegularFile == true else { continue }
            count += 1
            if count % 2000 == 0 { emit(.progress("Dosyalar listeleniyor", count, 0, failed)) }
            let size = UInt64(values?.fileSize ?? 0)
            if size >= minSize { bySize[size, default: []].append(url) }
        }
        errors = failed
        return bySize
    }

    /// SHA-256 özeti. limit verilirse yalnızca ilk limit bayt okunur.
    private nonisolated static func digest(of url: URL, limit: Int?) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        while remaining > 0 {
            if Task.isCancelled { return nil }
            let chunk: Data? = try? handle.read(upToCount: min(1 << 20, remaining))
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            if limit != nil { remaining -= chunk.count }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

struct DuplicatesPage: View {
    @ObservedObject var finder: DuplicateFinder

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Yinelenen dosyalar").font(.title2.weight(.semibold))
                Spacer()
                if finder.isScanning {
                    ProgressView().controlSize(.small)
                    Text(progressText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Button("Durdur") { finder.cancel() }.glassButton().controlSize(.small)
                } else if !finder.groups.isEmpty {
                    Text("\(formatBytes(finder.totalWasted)) boşa").font(.headline.monospacedDigit())
                }
            }
            HStack(spacing: 10) {
                Text("En küçük boyut").font(.caption).foregroundStyle(.secondary)
                Picker("Boyut", selection: $finder.minSizeIndex) {
                    ForEach(Array(DuplicateFinder.minSizes.enumerated()), id: \.offset) { index, item in
                        Text(item.label).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                Button { finder.scan() } label: { Label("Tara", systemImage: "magnifyingglass") }
                    .glassProminentButton()
                    .disabled(finder.isScanning)
            }
            if finder.finished, finder.inaccessible > 0 {
                Text("\(finder.inaccessible) öğeye erişilemedi (izin yok). Sonuçlar eksik olabilir.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if let notice = finder.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                GlassGroup(spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) { content }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollClipDisabled()
            Text("Tarama ev klasörünü okur, hiçbir şey değiştirmez. Gizli klasörler ve ~/Library taranmaz. APFS klonları gerçekte yer kaplamayabilir. Her gruptaki son kopya taşınamaz.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var progressText: String {
        finder.total > 0 ? "\(finder.phase) \(finder.done)/\(finder.total)" : "\(finder.phase) \(finder.done)"
    }

    @ViewBuilder
    private var content: some View {
        if finder.groups.isEmpty {
            Text(finder.isScanning ? "Taranıyor..." : (finder.finished ? "Yinelenen dosya bulunamadı." : "Henüz sonuç yok. Tara'ya basın."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
        } else {
            ForEach(finder.groups) { group in
                card(group)
            }
        }
    }

    private func card(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CardHeader(
                symbol: "square.on.square",
                title: "\(group.files.count) kopya · \(formatBytes(group.size))",
                trailing: "\(formatBytes(group.wasted)) boşa"
            )
            ForEach(group.files, id: \.self) { url in
                row(url, group: group)
            }
        }
        .padding(12)
        .glassCard()
    }

    private func row(_ url: URL, group: DuplicateGroup) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(url.lastPathComponent).font(.subheadline).lineLimit(1).truncationMode(.middle)
                Text(url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 8)
            if finder.pendingTrash == url {
                Button("Taşı") { finder.moveToTrash(url, from: group.id) }
                    .glassButton()
                    .controlSize(.small)
                    .fixedSize()
                Button("Vazgeç") { finder.pendingTrash = nil }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            } else {
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Image(systemName: "magnifyingglass.circle") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Finder'da göster")
                let allowed = DiskAnalyzer.canTrash(url) && group.files.count > 1
                Button { finder.pendingTrash = url } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                    .foregroundStyle(allowed ? Color.secondary : Color.secondary.opacity(0.3))
                    .disabled(!allowed)
                    .help(allowed ? "Çöp Kutusu'na taşı" : "Bu öğe korumalı")
            }
        }
    }
}
