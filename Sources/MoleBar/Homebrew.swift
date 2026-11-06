import AppKit
import SwiftUI

struct BrewUpdate: Identifiable, Equatable {
    let name: String
    let installed: String
    let latest: String
    let isCask: Bool
    let isPinned: Bool
    var id: String { (isCask ? "cask:" : "formula:") + name }
}

/// Homebrew güncelleme denetimi. `brew outdated` salt okunur çalışır.
/// MoleBar `brew upgrade` çalıştırmaz. Komut panoya kopyalanır, Terminal'de siz çalıştırırsınız.
enum Homebrew {
    static let candidatePaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

    static var executable: String? {
        candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// `brew outdated --json=v2` çıktısını çözer. Bozuk girdi boş liste verir.
    static func parse(_ data: Data) -> [BrewUpdate] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        func entries(_ key: String, isCask: Bool) -> [BrewUpdate] {
            (root[key] as? [[String: Any]] ?? []).compactMap { item in
                guard let name = item["name"] as? String, let latest = item["current_version"] as? String else { return nil }
                // Formüllerde sürüm listesi, cask'lerde tek metin gelir. Son kurulu sürüm alınır.
                let installed: String
                if let list = item["installed_versions"] as? [String] { installed = list.first ?? "?" }
                else { installed = item["installed_versions"] as? String ?? "?" }
                return BrewUpdate(name: name, installed: installed, latest: latest, isCask: isCask,
                                  isPinned: item["pinned"] as? Bool ?? false)
            }
        }
        return entries("formulae", isCask: false) + entries("casks", isCask: true)
    }

    /// Panoya kopyalanacak komut. Ad yalnızca güvenli karakterler içeriyorsa komuta girer.
    static func upgradeCommand(for name: String?) -> String {
        guard let name, !name.isEmpty,
              name.allSatisfy({ $0.isLetter || $0.isNumber || "-_.@+/".contains($0) }) else { return "brew upgrade" }
        return "brew upgrade \(name)"
    }

    /// Otomatik güncellemeyi ve analitiği kapatır. 30 saniyede bitmezse süreç sonlandırılır.
    nonisolated static func fetch() -> [BrewUpdate] {
        guard let path = executable else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["outdated", "--json=v2"]
        var environment = ProcessInfo.processInfo.environment
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["HOMEBREW_NO_ANALYTICS"] = "1"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return parse(data)
    }
}

@MainActor
final class HomebrewModel: ObservableObject {
    @Published private(set) var updates: [BrewUpdate] = []
    @Published private(set) var loading = false
    @Published private(set) var loaded = false
    @Published var notice: String?

    var isInstalled: Bool { Homebrew.executable != nil }

    func reload() {
        guard !loading, isInstalled else { return }
        loading = true
        Task {
            updates = await Task.detached(priority: .utility) { Homebrew.fetch() }.value
            loading = false
            loaded = true
        }
    }

    func copyUpgrade(_ name: String?) {
        let command = Homebrew.upgradeCommand(for: name)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        notice = "Komut panoya kopyalandı: \(command). Terminal'de siz çalıştırın."
    }
}

/// Araçlar sayfasında Homebrew güncellemeleri. MoleBar güncellemeyi kendisi çalıştırmaz.
struct HomebrewCard: View {
    @StateObject private var model = HomebrewModel()

    var body: some View {
        if model.isInstalled { content }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardHeader(symbol: "shippingbox", title: "Homebrew güncellemeleri",
                           trailing: model.loaded ? "\(model.updates.count) paket" : "")
                if model.loading { ProgressView().controlSize(.small) }
                Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .glassButton()
                    .controlSize(.small)
                    .disabled(model.loading)
                    .help("Yeniden denetle")
                    .accessibilityLabel("Yeniden denetle")
            }
            if model.updates.isEmpty {
                Text(model.loaded ? "Tüm paketler güncel." : "Denetleniyor...").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(model.updates.prefix(12)) { update in
                    HStack(spacing: 8) {
                        Text(verbatim: update.name).font(.caption).lineLimit(1)
                        if update.isCask { Text("cask").font(.caption2).foregroundStyle(.secondary) }
                        if update.isPinned { Text("sabit").font(.caption2).foregroundStyle(.orange) }
                        Spacer(minLength: 6)
                        Text(verbatim: "\(update.installed) → \(update.latest)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if model.updates.count > 12 {
                    Text("\(model.updates.count - 12) paket daha var.").font(.caption2).foregroundStyle(.secondary)
                }
                Button { model.copyUpgrade(nil) } label: { Label("Tümü için komutu kopyala", systemImage: "doc.on.doc") }
                    .glassButton()
                    .controlSize(.small)
            }
            if let notice = model.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("Güncelleme denetimi salt okunurdur. MoleBar brew upgrade çalıştırmaz.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .onAppear { if !model.loaded { model.reload() } }
    }
}
