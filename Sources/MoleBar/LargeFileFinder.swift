import AppKit
import SwiftUI

enum FileKind: String, CaseIterable {
    case all = "Hepsi"
    case image = "İmaj"
    case archive = "Arşiv"
    case video = "Video"
    case other = "Diğer"

    static func of(_ url: URL) -> FileKind {
        switch url.pathExtension.lowercased() {
        case "dmg", "iso", "img", "raw", "qcow2", "vmdk", "vdi", "sparseimage", "sparsebundle", "vhd", "vhdx": return .image
        case "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "zst", "pkg": return .archive
        case "mov", "mp4", "mkv", "avi", "m4v", "webm", "wmv", "mts": return .video
        default: return .other
        }
    }
}

struct LargeFile: Identifiable {
    let url: URL
    let bytes: UInt64
    var id: URL { url }
    var name: String { url.lastPathComponent }
    var kind: FileKind { FileKind.of(url) }
    var folder: String {
        url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

/// Ev klasöründe eşiğin üstündeki dosyaları bulur. Tarama salt okunurdur.
/// Sembolik bağlantılar ve paket (.app) içleri atlanır. Bağlı birim sınırları aşılmaz.
@MainActor
final class LargeFileFinder: ObservableObject {
    static let thresholds: [(label: String, bytes: UInt64)] = [
        ("100 MB", 100 << 20), ("500 MB", 500 << 20), ("1 GB", 1 << 30)
    ]

    @Published private(set) var files: [LargeFile] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scanned = 0
    @Published private(set) var inaccessible = 0
    @Published var thresholdIndex = 1
    @Published var kind: FileKind = .all
    @Published var pendingTrash: URL?
    @Published var notice: String?

    private var task: Task<Void, Never>?
    private var started = false
    private let maxResults = 200

    var thresholdBytes: UInt64 { Self.thresholds[thresholdIndex].bytes }
    var totalBytes: UInt64 { files.reduce(0) { $0 + $1.bytes } }
    var visibleFiles: [LargeFile] { kind == .all ? files : files.filter { $0.kind == kind } }
    var visibleBytes: UInt64 { visibleFiles.reduce(0) { $0 + $1.bytes } }

    func scanIfNeeded() {
        guard !started else { return }
        scan()
    }

    func scan() {
        started = true
        task?.cancel()
        files = []
        scanned = 0
        inaccessible = 0
        pendingTrash = nil
        isScanning = true
        let limit = thresholdBytes
        let cap = maxResults
        task = Task { [weak self] in
            let stream = Self.stream(limit: limit)
            for await event in stream {
                if Task.isCancelled { break }
                guard let self else { return }
                switch event {
                case .progress(let count, let errors):
                    self.scanned = count
                    self.inaccessible = errors
                case .hit(let file):
                    self.files.append(file)
                    self.files.sort { $0.bytes > $1.bytes }
                    if self.files.count > cap { self.files.removeLast() }
                }
            }
            self?.isScanning = false
            if let self, !Task.isCancelled { ReclaimStore.save(.large, bytes: self.totalBytes) }
        }
    }

    func cancel() {
        task?.cancel()
        isScanning = false
    }

    func moveToTrash(_ file: LargeFile) {
        pendingTrash = nil
        guard TrashGuard.canTrash(file.url) else {
            notice = "\(file.name) korumalı bir yolda. Finder'da gösterin."
            return
        }
        do {
            try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
            files.removeAll { $0.url == file.url }
            ReclaimStore.save(.large, bytes: totalBytes)
            notice = "\(file.name) Çöp Kutusu'na taşındı. Finder'dan geri alınabilir."
        } catch {
            notice = "\(file.name) taşınamadı: \(error.localizedDescription)"
        }
    }

    // MARK: Tarama

    private enum Event {
        case progress(Int, Int)
        case hit(LargeFile)
    }

    private nonisolated static func stream(limit: UInt64) -> AsyncStream<Event> {
        AsyncStream { continuation in
            let worker = Task.detached {
                walkHome(limit: limit) { continuation.yield($0) }
                continuation.finish()
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    /// Senkron gezinti. Async bağlamda NSEnumerator kullanılmaz.
    private nonisolated static func walkHome(limit: UInt64, emit: (Event) -> Void) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isVolumeKey, .totalFileAllocatedSizeKey]
        let home = FileManager.default.homeDirectoryForCurrentUser
        var errors = 0
        guard let enumerator = FileManager.default.enumerator(
            at: home,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in errors += 1; return true }
        ) else { return }

        var count = 0
        for case let url as URL in enumerator {
            if Task.isCancelled { break }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if values?.isVolume == true { enumerator.skipDescendants() }
                continue
            }
            guard values?.isRegularFile == true else { continue }
            count += 1
            if count % 2000 == 0 { emit(.progress(count, errors)) }
            let size = UInt64(values?.totalFileAllocatedSize ?? 0)
            if size >= limit { emit(.hit(LargeFile(url: url, bytes: size))) }
        }
        emit(.progress(count, errors))
    }
}

struct LargeFilesPage: View {
    @ObservedObject var finder: LargeFileFinder

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Büyük dosyalar").font(.title2.weight(.semibold))
                Spacer()
                if finder.isScanning {
                    ProgressView().controlSize(.small)
                    Text("\(finder.scanned) dosya").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Button("Durdur") { finder.cancel() }.glassButton().controlSize(.small)
                } else if !finder.visibleFiles.isEmpty {
                    Text(formatBytes(finder.visibleBytes)).font(.headline.monospacedDigit())
                }
            }
            HStack(spacing: 10) {
                Text("Eşik").font(.caption).foregroundStyle(.secondary)
                Picker("Eşik", selection: $finder.thresholdIndex) {
                    ForEach(Array(LargeFileFinder.thresholds.enumerated()), id: \.offset) { index, item in
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
            Picker("Tür", selection: $finder.kind) {
                ForEach(FileKind.allCases, id: \.self) { kind in
                    let count = kind == .all ? finder.files.count : finder.files.filter { $0.kind == kind }.count
                    Text("\(kind.rawValue) \(count)").tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)
            if !finder.isScanning, finder.scanned > 0 {
                Text("\(finder.scanned) dosya tarandı." + (finder.inaccessible > 0 ? " \(finder.inaccessible) öğeye erişilemedi (izin yok). Sonuçlar eksik. Sistem Ayarları > Gizlilik > Tam Disk Erişimi altında MoleBar'a izin verin." : ""))
                    .font(.caption2)
                    .foregroundStyle(finder.inaccessible > 0 ? Color.orange : Color.secondary)
            }
            if let notice = finder.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                GlassGroup(spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) { content }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()
                }
            }
            .shadowSafeScroll()
            Text("Tarama ev klasörünü okur ve hiçbir şey değiştirmez. Çöp ikonu dosyayı Çöp Kutusu'na taşır; kalıcı silmez. Uygulama paketlerinin içi taranmaz.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .onAppear { finder.scanIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if finder.visibleFiles.isEmpty {
            Text(finder.isScanning ? "Taranıyor..." : (finder.files.isEmpty ? "Henüz sonuç yok. Tara'ya basın." : "Bu türde dosya yok."))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(finder.visibleFiles) { file in
                row(file)
                Divider().opacity(0.4)
            }
        }
    }

    private func row(_ file: LargeFile) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                .resizable()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(file.name).font(.subheadline).lineLimit(1).truncationMode(.middle)
                Text(file.folder).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 8)
            Text(formatBytes(file.bytes)).font(.subheadline.weight(.medium).monospacedDigit())
            if finder.pendingTrash == file.url {
                Button("Taşı") { finder.moveToTrash(file) }
                    .glassButton()
                    .controlSize(.small)
                    .fixedSize()
                Button("Vazgeç") { finder.pendingTrash = nil }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            } else {
                Button { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } label: { Image(systemName: "magnifyingglass.circle") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Finder'da göster")
                let allowed = TrashGuard.canTrash(file.url)
                Button { finder.pendingTrash = file.url } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                    .foregroundStyle(allowed ? Color.secondary : Color.secondary.opacity(0.3))
                    .disabled(!allowed)
                    .help(allowed ? "Çöp Kutusu'na taşı" : "Bu öğe korumalı")
            }
        }
        .padding(.vertical, 7)
    }
}
