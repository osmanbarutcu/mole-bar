import AppKit
import SwiftUI

enum LaunchScope: CaseIterable {
    case userAgent, systemAgent, systemDaemon

    var title: String {
        switch self {
        case .userAgent: return L("Kullanıcı ajanları")
        case .systemAgent: return L("Sistem ajanları")
        case .systemDaemon: return L("Sistem servisleri")
        }
    }

    var directory: URL {
        switch self {
        case .userAgent: return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        case .systemAgent: return URL(fileURLWithPath: "/Library/LaunchAgents")
        case .systemDaemon: return URL(fileURLWithPath: "/Library/LaunchDaemons")
        }
    }
}

struct LaunchItem: Identifiable {
    let plist: URL
    let scope: LaunchScope
    let label: String
    let program: String?
    let runAtLoad: Bool
    let keepAlive: Bool
    let missing: Bool
    var id: URL { plist }
}

/// Açılışta veya arka planda çalışan öğeleri listeler. Yalnızca plist okur. MoleBar hiçbir öğeyi değiştirmez.
enum LaunchItems {
    static func scan(
        _ sources: [(URL, LaunchScope)] = LaunchScope.allCases.map { ($0.directory, $0) },
        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [LaunchItem] {
        sources.flatMap { directory, scope -> [LaunchItem] in
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            return files.filter { $0.pathExtension == "plist" }.compactMap { file in
                guard let data = try? Data(contentsOf: file),
                      let object = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                else { return nil }
                let program = object["Program"] as? String ?? (object["ProgramArguments"] as? [String])?.first
                let keepAlive = (object["KeepAlive"] as? Bool) ?? (object["KeepAlive"] is [String: Any])
                return LaunchItem(
                    plist: file, scope: scope,
                    label: object["Label"] as? String ?? file.deletingPathExtension().lastPathComponent,
                    program: program,
                    runAtLoad: object["RunAtLoad"] as? Bool ?? false,
                    keepAlive: keepAlive,
                    missing: program.map { $0.hasPrefix("/") && !exists($0) } ?? false
                )
            }
        }
        .sorted { $0.label.lowercased() < $1.label.lowercased() }
    }
}

@MainActor
final class LaunchItemsModel: ObservableObject {
    @Published private(set) var items: [LaunchItem] = []
    @Published private(set) var checked = false

    func reload() {
        Task {
            items = await Task.detached { LaunchItems.scan() }.value
            checked = true
        }
    }

    func items(in scope: LaunchScope) -> [LaunchItem] { items.filter { $0.scope == scope } }
}

/// Araçlar sayfasında tüm başlatma öğelerini gösterir. Salt okunur.
struct LaunchItemsCard: View {
    @StateObject private var model = LaunchItemsModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "bolt.horizontal", title: "Başlatma öğeleri", trailing: model.checked ? L("%ld öğe", model.items.count) : "")
            if model.items.isEmpty {
                Text(model.checked ? L("Başlatma öğesi bulunamadı.") : L("Taranıyor..."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(LaunchScope.allCases, id: \.title) { scope in
                    let rows = model.items(in: scope)
                    if !rows.isEmpty {
                        DisclosureGroup("\(scope.title) (\(rows.count))") {
                            ForEach(rows) { row($0) }
                        }
                        .font(.subheadline)
                    }
                }
                Text("MoleBar bu öğeleri değiştirmez. Kapatmak için Sistem Ayarları > Genel > Giriş Öğeleri'ni veya ilgili uygulamanın ayarını kullanın.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .onAppear { model.reload() }
    }

    private func row(_ item: LaunchItem) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(item.label).font(.caption).lineLimit(1).truncationMode(.middle)
                Text(tags(item)).font(.caption2).foregroundStyle(item.missing ? Color.orange : Color.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Button { NSWorkspace.shared.activateFileViewerSelecting([item.plist]) } label: { Image(systemName: "magnifyingglass.circle") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Finder'da göster")
                .accessibilityLabel("Finder'da göster")
        }
        .padding(.vertical, 2)
    }

    private func tags(_ item: LaunchItem) -> String {
        var parts: [String] = []
        if item.missing { parts.append(L("hedef yok")) }
        if item.runAtLoad { parts.append(L("açılışta")) }
        if item.keepAlive { parts.append(L("sürekli")) }
        if parts.isEmpty { parts.append(L("istek üzerine")) }
        return parts.joined(separator: " · ")
    }
}
