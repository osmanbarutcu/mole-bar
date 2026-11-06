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
    @Published var includeHidden = false
    @Published var pendingTrash: URL?
    @Published var notice: String?
    /// Toplu kural: true ise her grupta en eski kopya kalır, false ise en yeni kopya kalır.
    @Published var keepOldest = true
    @Published var confirmingBulk = false
    /// Son tarama gizli klasörleri ve Library'yi kapsadıysa toplu işlem kapalıdır.
    @Published private(set) var scannedHidden = false

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
        confirmingBulk = false
        scannedHidden = includeHidden
        isScanning = true
        let minSize = Self.minSizes[minSizeIndex].bytes
        let hidden = includeHidden
        let cap = maxGroups
        task = Task { [weak self] in
            for await event in Self.stream(minSize: minSize, includeHidden: hidden) {
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
            if self.finished { ReclaimStore.save(.duplicates, bytes: self.totalWasted) }
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
        guard TrashGuard.canTrash(url) else {
            notice = "\(url.lastPathComponent) korumalı bir yolda. Finder'da gösterin."
            return
        }
        do {
            try TrashGuard.trash(url, bytes: groups[index].size, source: "Yinelenenler")
            groups[index].files.removeAll { $0 == url }
            if groups[index].files.count < 2 { groups.remove(at: index) }
            ReclaimStore.save(.duplicates, bytes: totalWasted)
            notice = "\(url.lastPathComponent) Çöp Kutusu'na taşındı. Finder'dan geri alınabilir."
        } catch {
            notice = "\(url.lastPathComponent) taşınamadı: \(error.localizedDescription)"
        }
    }

    /// Toplu kuralın taşıyacağı kopyalar. Her grupta tek kopya kalır. Korumalı yollar taşınmaz.
    func bulkPlan() -> [(url: URL, bytes: UInt64, groupID: String)] {
        Self.plan(groups: groups, keepOldest: keepOldest, canTrash: TrashGuard.canTrash, modified: Self.modificationDate)
    }

    nonisolated static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantFuture
    }

    /// Saf mantık: dosya sistemine dokunmaz, bu yüzden test edilebilir.
    nonisolated static func plan(
        groups: [DuplicateGroup],
        keepOldest: Bool,
        canTrash: (URL) -> Bool,
        modified: (URL) -> Date
    ) -> [(url: URL, bytes: UInt64, groupID: String)] {
        var result: [(url: URL, bytes: UInt64, groupID: String)] = []
        for group in groups where group.files.count > 1 {
            let dated = group.files.map { ($0, modified($0)) }
            // Eşit tarihte ilk dosya kalır. Böylece sonuç kararlıdır.
            var keep = dated[0]
            for entry in dated.dropFirst() where keepOldest ? entry.1 < keep.1 : entry.1 > keep.1 { keep = entry }
            for (url, _) in dated where url != keep.0 && canTrash(url) {
                result.append((url, group.size, group.id))
            }
        }
        return result
    }

    func applyBulk() {
        confirmingBulk = false
        var moved: UInt64 = 0
        var failed = 0
        for item in bulkPlan() {
            guard let index = groups.firstIndex(where: { $0.id == item.groupID }), groups[index].files.count > 1 else { continue }
            do {
                try TrashGuard.trash(item.url, bytes: item.bytes, source: "Yinelenenler (toplu)")
                groups[index].files.removeAll { $0 == item.url }
                if groups[index].files.count < 2 { groups.remove(at: index) }
                moved += item.bytes
            } catch { failed += 1 }
        }
        ReclaimStore.save(.duplicates, bytes: totalWasted)
        notice = failed == 0
            ? "\(formatBytes(moved)) Çöp Kutusu'na taşındı. Finder'dan geri alınabilir."
            : "\(formatBytes(moved)) taşındı. \(failed) dosya taşınamadı."
    }

    // MARK: Tarama

    private enum Event {
        case progress(String, Int, Int, Int)
        case group(DuplicateGroup)
    }

    private nonisolated static func stream(minSize: UInt64, includeHidden: Bool) -> AsyncStream<Event> {
        AsyncStream { continuation in
            let worker = Task.detached {
                run(minSize: minSize, includeHidden: includeHidden) { continuation.yield($0) }
                continuation.finish()
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    /// Senkron iş akışı. Async bağlamda NSEnumerator kullanılmaz.
    private nonisolated static func run(minSize: UInt64, includeHidden: Bool, emit: (Event) -> Void) {
        var errors = 0
        let bySize = collect(minSize: minSize, includeHidden: includeHidden, errors: &errors, emit: emit)
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

    private nonisolated static func collect(minSize: UInt64, includeHidden: Bool, errors: inout Int, emit: (Event) -> Void) -> [UInt64: [URL]] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isVolumeKey, .fileSizeKey]
        let home = FileManager.default.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library").path
        var failed = 0
        guard let enumerator = FileManager.default.enumerator(
            at: home,
            includingPropertiesForKeys: keys,
            options: includeHidden ? [.skipsPackageDescendants] : [.skipsPackageDescendants, .skipsHiddenFiles],
            errorHandler: { _, _ in failed += 1; return true }
        ) else { return [:] }

        var bySize: [UInt64: [URL]] = [:]
        var count = 0
        for case let url as URL in enumerator {
            if Task.isCancelled { break }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                let skipLibrary = !includeHidden && url.path == library
                // Çöp Kutusu ve git nesneleri her durumda atlanır.
                let name = url.lastPathComponent
                if skipLibrary || values?.isVolume == true || name == ".Trash" || name == ".git" { enumerator.skipDescendants() }
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
        VStack(alignment: .leading, spacing: 14) {
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
            Toggle("Gizli klasörleri ve Library'yi de tara", isOn: $finder.includeHidden)
                .toggleStyle(RightSwitchStyle())
                .font(.subheadline)
                .disabled(finder.isScanning)
            if finder.includeHidden {
                Text("Dikkat: uygulama verisi ve önbellek kopyaları bilerek oluşur. Bir kopyayı taşımak uygulamayı bozabilir. Yalnızca ne olduğunu bildiğiniz dosyaları taşıyın.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if finder.finished, finder.inaccessible > 0 {
                Text("\(finder.inaccessible) öğeye erişilemedi (izin yok). Sonuçlar eksik olabilir.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if let notice = finder.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
            if !finder.groups.isEmpty, !finder.isScanning { bulkBar }
            ScrollView {
                GlassGroup(spacing: 12) {
                    VStack(alignment: .leading, spacing: 14) { content }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .shadowSafeScroll()
            Text("Tarama ev klasörünü okur, hiçbir şey değiştirmez. Gizli klasörler ve ~/Library varsayılan olarak taranmaz. APFS klonları gerçekte yer kaplamayabilir. Her gruptaki son kopya taşınamaz.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }

    @ViewBuilder
    private var bulkBar: some View {
        let plan = finder.bulkPlan()
        let bytes = plan.reduce(UInt64(0)) { $0 + $1.bytes }
        HStack(spacing: 10) {
            Text("Her grupta koru").font(.caption).foregroundStyle(.secondary)
            Picker("Koru", selection: $finder.keepOldest) {
                Text("En eski").tag(true)
                Text("En yeni").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
            .onChange(of: finder.keepOldest) { _, _ in finder.confirmingBulk = false }
            Spacer(minLength: 8)
            if finder.scannedHidden {
                Text("Gizli klasör taramasında toplu işlem kapalı.").font(.caption2).foregroundStyle(.orange)
            } else if finder.confirmingBulk {
                Text("\(plan.count) dosya · \(formatBytes(bytes)) taşınacak").font(.caption)
                Button("Taşı") { finder.applyBulk() }.glassProminentButton().controlSize(.small)
                Button("Vazgeç") { finder.confirmingBulk = false }.glassButton().controlSize(.small)
            } else {
                Button { finder.confirmingBulk = true } label: { Label("Kalanları taşı", systemImage: "trash") }
                    .glassButton()
                    .controlSize(.small)
                    .disabled(plan.isEmpty)
            }
        }
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
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
        } else {
            ForEach(finder.groups) { group in
                card(group)
            }
        }
    }

    private func card(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(
                symbol: "square.on.square",
                title: "\(group.files.count) kopya · \(formatBytes(group.size))",
                trailing: "\(formatBytes(group.wasted)) boşa"
            )
            ForEach(group.files, id: \.self) { url in
                row(url, group: group)
            }
        }
        .padding(16)
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
                let allowed = TrashGuard.canTrash(url) && group.files.count > 1
                Button { finder.pendingTrash = url } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                    .foregroundStyle(allowed ? Color.secondary : Color.secondary.opacity(0.3))
                    .disabled(!allowed)
                    .help(allowed ? "Çöp Kutusu'na taşı" : "Bu öğe korumalı")
            }
        }
    }
}
