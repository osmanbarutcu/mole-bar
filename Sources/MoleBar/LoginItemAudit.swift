import AppKit
import SwiftUI

struct StaleLoginItem: Identifiable {
    let plist: URL
    let target: String
    var id: URL { plist }
    var name: String { plist.deletingPathExtension().lastPathComponent }
}

enum LoginItemAudit {
    /// Hedef programı bulunmayan kullanıcı başlatma öğelerini döndürür. Yalnızca okur, hiçbir şeyi değiştirmez.
    /// Hedef `Program` veya `ProgramArguments[0]` alanından gelir. Mutlak olmayan yollar (ör. `python3`) atlanır.
    static func stale(in directory: URL, exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [StaleLoginItem] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "plist" }.compactMap { file in
            guard let data = try? Data(contentsOf: file),
                  let object = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { return nil }
            let program = object["Program"] as? String ?? (object["ProgramArguments"] as? [String])?.first
            guard let program, program.hasPrefix("/"), !exists(program) else { return nil }
            return StaleLoginItem(plist: file, target: program)
        }
        .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    static var userAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
    }
}

@MainActor
final class LoginItemAuditModel: ObservableObject {
    @Published private(set) var items: [StaleLoginItem] = []
    @Published private(set) var checked = false

    func reload() {
        Task {
            items = await Task.detached { LoginItemAudit.stale(in: LoginItemAudit.userAgentsDirectory) }.value
            checked = true
        }
    }
}

/// Araçlar sayfasında hedefi kayıp başlatma öğelerini listeler. MoleBar bunları silmez.
struct LoginItemAuditCard: View {
    @StateObject private var model = LoginItemAuditModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "power", title: "Eski giriş öğeleri", trailing: model.checked ? "\(model.items.count) öğe" : "")
            if model.items.isEmpty {
                Text(model.checked ? "Hedefi eksik öğe yok." : "Taranıyor...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.items) { item in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.name).font(.subheadline).lineLimit(1).truncationMode(.middle)
                            Text("Eksik: \(item.target.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 6)
                        Button { NSWorkspace.shared.activateFileViewerSelecting([item.plist]) } label: { Image(systemName: "magnifyingglass.circle") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Finder'da göster")
                    }
                }
                Text("Hedef program yoksa öğe çalışmaz. MoleBar silmez. Tanıdığınız öğeyi Finder'dan siz kaldırın.")
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
}
