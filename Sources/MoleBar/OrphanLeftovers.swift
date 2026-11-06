import AppKit
import SwiftUI

struct OrphanItem: Identifiable {
    let url: URL
    let bundleID: String
    let area: String
    let bytes: UInt64
    var id: URL { url }
}

/// Kurulu uygulaması olmayan, paket kimliği adlı `~/Library` kalıntılarını bulur. Salt okunur.
enum OrphanScanner {
    /// Kullanıcı verisi taşıyan `Containers` ve `Preferences` taranmaz.
    static let areas = ["Caches", "Saved Application State", "HTTPStorages", "Logs", "Application Support"]

    private static let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._")

    /// Dosya adından paket kimliğini çıkarır. Kimlik biçiminde değilse, Apple veya MoleBar ise nil döner.
    static func bundleID(fromName name: String) -> String? {
        var id = name
        if id.hasSuffix(".savedState") { id = String(id.dropLast(".savedState".count)) }
        guard id.split(separator: ".", omittingEmptySubsequences: false).count >= 3,
              id.unicodeScalars.allSatisfy(allowed.contains),
              !id.hasPrefix("."), !id.hasSuffix("."),
              !id.hasPrefix("com.apple."), id != "local.molebar" else { return nil }
        return id
    }

    /// Kurulu bir uygulamanın kimliği aynıysa veya nokta sınırında önek ise kalıntı o uygulamaya aittir.
    static func isOwned(_ id: String, by installed: Set<String>) -> Bool {
        let lower = id.lowercased()
        return installed.contains { app in
            let appID = app.lowercased()
            return lower == appID || lower.hasPrefix(appID + ".") || appID.hasPrefix(lower + ".")
        }
    }

    /// Üretici: paket kimliğinin ilk iki parçası (örn. `com.microsoft`).
    static func vendor(of id: String) -> String {
        id.lowercased().split(separator: ".").prefix(2).joined(separator: ".")
    }

    /// Kalıntı yetim sayılır: kurulu uygulamaya ait değildir ve aynı üreticinin kurulu uygulaması yoktur.
    /// İkinci koşul yanlış pozitifi azaltır: güncelleyiciler ve yardımcılar /Applications dışında durur.
    static func isOrphan(_ id: String, installed: Set<String>) -> Bool {
        guard !isOwned(id, by: installed) else { return false }
        let vendorID = vendor(of: id)
        return !installed.contains { vendor(of: $0) == vendorID }
    }

    static func orphanIDs(names: [String], installed: Set<String>) -> [String] {
        names.compactMap { bundleID(fromName: $0) }.filter { isOrphan($0, installed: installed) }
    }

    /// Kurulu ve çalışan uygulamaların paket kimlikleri. Klasörler bir düzey derine bakılır.
    static func installedBundleIDs() -> Set<String> {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = ["/Applications", "/System/Applications", "/Applications/Utilities"].map { URL(fileURLWithPath: $0) }
            + [home.appendingPathComponent("Applications")]
        var ids = Set<String>()
        func collect(_ dir: URL, depth: Int) {
            let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for url in items {
                if url.pathExtension == "app" {
                    if let id = Bundle(url: url)?.bundleIdentifier { ids.insert(id) }
                } else if depth > 0, (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    collect(url, depth: depth - 1)
                }
            }
        }
        for root in roots { collect(root, depth: 1) }
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier { ids.insert(id) }
        }
        return ids
    }

    static func scan() -> [OrphanItem] {
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        let installed = installedBundleIDs()
        // Kurulu uygulama listesi boşsa tarama güvenilmezdir. Hiçbir şey gösterilmez.
        guard !installed.isEmpty else { return [] }
        var result: [OrphanItem] = []
        for area in areas {
            let dir = library.appendingPathComponent(area)
            let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for url in urls {
                guard let id = bundleID(fromName: url.lastPathComponent), isOrphan(id, installed: installed),
                      TrashGuard.canTrash(url) else { continue }
                let bytes = FileSizer.size(of: url)
                if bytes > 0 { result.append(OrphanItem(url: url, bundleID: id, area: area, bytes: bytes)) }
            }
        }
        return result.sorted { $0.bytes > $1.bytes }
    }
}

@MainActor
final class OrphanModel: ObservableObject {
    @Published private(set) var items: [OrphanItem] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scanned = false
    @Published var selected = Set<URL>()
    @Published var confirming = false
    @Published var notice: String?

    var selectedBytes: UInt64 { items.filter { selected.contains($0.url) }.reduce(0) { $0 + $1.bytes } }
    var totalBytes: UInt64 { items.reduce(0) { $0 + $1.bytes } }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        confirming = false
        selected = []
        Task {
            items = await Task.detached(priority: .utility) { OrphanScanner.scan() }.value
            isScanning = false
            scanned = true
        }
    }

    func toggle(_ item: OrphanItem) {
        if selected.contains(item.url) { selected.remove(item.url) } else { selected.insert(item.url) }
        confirming = false
    }

    /// Seçilenleri Çöp Kutusu'na taşır. Geri alınabilir.
    func moveSelectedToTrash() {
        confirming = false
        var failed = 0
        var moved = Set<URL>()
        for item in items where selected.contains(item.url) {
            do {
                try TrashGuard.trash(item.url, bytes: item.bytes, source: "Yetim artıklar")
                moved.insert(item.url)
            } catch { failed += 1 }
        }
        items.removeAll { moved.contains($0.url) }
        selected = []
        notice = failed == 0
            ? "\(moved.count) öğe Çöp Kutusu'na taşındı. Finder'dan geri alınabilir."
            : "\(moved.count) öğe taşındı, \(failed) öğe taşınamadı."
    }
}

struct OrphanPage: View {
    @ObservedObject var model: OrphanModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Kurulu uygulaması olmayan kalıntılar").font(.subheadline.weight(.semibold))
                Spacer()
                if model.isScanning { ProgressView().controlSize(.small) }
                Button { model.scan() } label: { Label(model.scanned ? "Yeniden tara" : "Tara", systemImage: "magnifyingglass") }
                    .glassButton()
                    .disabled(model.isScanning)
            }
            if let notice = model.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            if model.isScanning && model.items.isEmpty {
                Text("Taranıyor...").font(.caption).foregroundStyle(.secondary)
            } else if model.scanned && model.items.isEmpty {
                Text("Yetim kalıntı bulunamadı.").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.items) { item in
                        HStack(spacing: 8) {
                            Image(systemName: model.selected.contains(item.url) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(model.selected.contains(item.url) ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(verbatim: item.bundleID).font(.subheadline).lineLimit(1).truncationMode(.middle)
                                Text(verbatim: item.area).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text(formatBytes(item.bytes)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6).padding(.horizontal, 8)
                        .contentShape(Rectangle())
                        .onTapGesture { model.toggle(item) }
                    }
                }
                .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassCard(cornerRadius: 16)
            .onAppear { if !model.scanned { model.scan() } }
            actions
            Text("Kalıntılar kurulu uygulamalarla paket kimliği üzerinden eşleşir. Uygulama başka bir diskteyse yanlış listelenebilir. Her şey Çöp Kutusu'na taşınır. Application Support içinde kullanıcı verisi olabilir, taşımadan önce kontrol edin.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if model.confirming {
            HStack {
                Text("\(formatBytes(model.selectedBytes)) Çöp Kutusu'na taşınacak.").font(.caption)
                Button("Taşı") { model.moveSelectedToTrash() }.glassProminentButton()
                Button("Vazgeç") { model.confirming = false }.glassButton()
            }
        } else if !model.selected.isEmpty {
            Button { model.confirming = true } label: {
                Label("Seçilenleri Çöp Kutusu'na taşı (\(formatBytes(model.selectedBytes)))", systemImage: "trash")
            }
            .glassButton()
        }
    }
}
