import AppKit
import SwiftUI

struct AppEntry: Identifiable {
    let url: URL
    let name: String
    let bundleID: String?
    var bytes: UInt64 = 0
    var sized = false
    var id: URL { url }
}

struct Leftover: Identifiable {
    let url: URL
    let bytes: UInt64
    var id: URL { url }
}

/// Uygulamaları ve ~/Library altındaki tam eşleşen artıklarını listeler.
/// Hiçbir şeyi kalıcı silmez. Seçilenleri Çöp Kutusu'na taşır.
@MainActor
final class AppUninstaller: ObservableObject {
    @Published private(set) var apps: [AppEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var leftovers: [Leftover] = []
    @Published var selected: AppEntry?
    @Published var confirming = false
    @Published var notice: String?

    private var loaded = false

    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        reload()
    }

    func reload() {
        isLoading = true
        selected = nil
        leftovers = []
        confirming = false
        Task {
            let found = await Task.detached { Self.findApps() }.value
            apps = found
            isLoading = false
            for app in found {
                let bytes = await Task.detached { FileSizer.size(of: app.url) }.value
                if let index = apps.firstIndex(where: { $0.id == app.id }) {
                    apps[index].bytes = bytes
                    apps[index].sized = true
                }
            }
            apps.sort { $0.bytes > $1.bytes }
        }
    }

    func select(_ app: AppEntry) {
        selected = app
        confirming = false
        leftovers = []
        Task {
            let found = await Task.detached { Self.findLeftovers(for: app) }.value
            if selected?.id == app.id { leftovers = found }
        }
    }

    var isSelectedRunning: Bool {
        guard let id = selected?.bundleID else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }

    var totalBytes: UInt64 {
        (selected?.bytes ?? 0) + leftovers.reduce(0) { $0 + $1.bytes }
    }

    /// Uygulamayı ve artıklarını Çöp Kutusu'na taşır. Geri alınabilir.
    func moveSelectedToTrash() {
        guard let app = selected, !isSelectedRunning else { return }
        confirming = false
        var failed: [String] = []
        for url in [app.url] + leftovers.map(\.url) {
            do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
            catch { failed.append(url.lastPathComponent) }
        }
        if failed.isEmpty {
            notice = "\(app.name) ve artıkları Çöp Kutusu'na taşındı. Finder'dan geri alınabilir."
        } else {
            notice = "Taşınamayan öğeler: \(failed.joined(separator: ", ")). Yönetici izni gerekebilir."
        }
        apps.removeAll { $0.id == app.id }
        selected = nil
        leftovers = []
    }

    // MARK: Tarama

    private nonisolated static func findApps() -> [AppEntry] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        var result: [AppEntry] = []
        for root in roots {
            let items = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for url in items where url.pathExtension == "app" {
                let id = Bundle(url: url)?.bundleIdentifier
                // Apple sistem uygulamaları ve MoleBar kendisi listelenmez.
                if let id, id.hasPrefix("com.apple.") || id == "local.molebar" { continue }
                result.append(AppEntry(url: url, name: url.deletingPathExtension().lastPathComponent, bundleID: id))
            }
        }
        return result
    }

    private nonisolated static func findLeftovers(for app: AppEntry) -> [Leftover] {
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        var names: [(dir: String, file: String)] = []
        if let id = app.bundleID {
            names += [
                ("Application Support", id), ("Caches", id), ("Preferences", "\(id).plist"),
                ("Containers", id), ("Saved Application State", "\(id).savedState"),
                ("HTTPStorages", id), ("WebKit", id), ("Application Scripts", id), ("Logs", id)
            ]
        }
        names += [("Application Support", app.name), ("Caches", app.name), ("Logs", app.name)]

        var seen = Set<URL>()
        var result: [Leftover] = []
        for (dir, file) in names {
            let url = library.appendingPathComponent(dir).appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: url.path), seen.insert(url).inserted else { continue }
            result.append(Leftover(url: url, bytes: FileSizer.size(of: url)))
        }
        return result.sorted { $0.bytes > $1.bytes }
    }
}

struct UninstallPage: View {
    @ObservedObject var model: AppUninstaller

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Uygulamalar").font(.title2.weight(.semibold))
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
                Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .glassButton()
                    .help("Yeniden tara")
            }
            if let notice = model.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 12) {
                list
                detail
            }
            Text("Kaldırma, uygulamayı ve ~/Library altındaki tam eşleşen artıklarını Çöp Kutusu'na taşır. Kalıcı silmez. Apple uygulamaları listelenmez.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .onAppear { model.loadIfNeeded() }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.apps) { app in
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                            .resizable()
                            .frame(width: 24, height: 24)
                        Text(app.name).font(.subheadline).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 8)
                        if app.sized {
                            Text(formatBytes(app.bytes))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView().controlSize(.mini)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(model.selected?.id == app.id ? Color.accentColor.opacity(0.18) : .clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { model.select(app) }
                }
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard(cornerRadius: 16)
    }

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let app = model.selected {
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                        .resizable()
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(app.name).font(.headline).lineLimit(1)
                        Text(app.bundleID ?? "Paket kimliği yok")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Divider().opacity(0.4)
                detailRow(icon: "app", title: app.url.path, bytes: app.bytes)
                if model.leftovers.isEmpty {
                    Text("Artık bulunamadı.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Artıklar").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(model.leftovers) { item in
                        detailRow(icon: "doc", title: item.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), bytes: item.bytes)
                    }
                }
                Spacer(minLength: 4)
                actions
            } else {
                Text("Listeden bir uygulama seçin.").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(12)
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassCard(cornerRadius: 16)
    }

    private func detailRow(icon: String, title: String, bytes: UInt64) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(.secondary).frame(width: 14)
            Text(title).font(.caption).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            Text(formatBytes(bytes)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if model.isSelectedRunning {
            Text("Uygulama çalışıyor. Önce çıkın.")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if model.confirming {
            Text("\(formatBytes(model.totalBytes)) Çöp Kutusu'na taşınacak.")
                .font(.caption)
            HStack {
                Button("Taşı") { model.moveSelectedToTrash() }
                    .glassProminentButton()
                Button("Vazgeç") { model.confirming = false }
                    .glassButton()
            }
        } else {
            Button { model.confirming = true } label: {
                Label("Çöp Kutusu'na taşı", systemImage: "trash").frame(maxWidth: .infinity)
            }
            .glassButton()
        }
    }
}
