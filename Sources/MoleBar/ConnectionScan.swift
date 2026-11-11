import SwiftUI

/// Bir sürecin kurulu dış bağlantıları.
struct ProcessConnections: Identifiable, Equatable {
    let pid: Int32
    let process: String
    /// En çok bağlantı kurulan uzak adres önce gelir. Biçim: `adres:port`.
    let remotes: [String]
    let count: Int
    var id: Int32 { pid }
}

/// Kurulu TCP bağlantılarını süreç başına özetler. `lsof` ile salt okunur çalışır.
/// Uzak adresler yerelde kalır. IP'den ülke bulmak için dış servis çağrılmaz.
enum ConnectionScan {
    /// `host:port` veya `[ipv6]:port` metnini böler.
    static func splitEndpoint(_ text: String) -> (host: String, port: String)? {
        if text.hasPrefix("[") {
            guard let close = text.firstIndex(of: "]"), text.index(after: close) < text.endIndex,
                  text[text.index(after: close)] == ":" else { return nil }
            let host = String(text[text.index(after: text.startIndex)..<close])
            let port = String(text[text.index(close, offsetBy: 2)...])
            return host.isEmpty || port.isEmpty ? nil : (host, port)
        }
        guard let colon = text.lastIndex(of: ":") else { return nil }
        let host = String(text[..<colon])
        let port = String(text[text.index(after: colon)...])
        return host.isEmpty || port.isEmpty ? nil : (host, port)
    }

    /// Döngü, özel ağ ve bağlantı-yerel adresler. Bunlar internete çıkmaz.
    static func isLocalHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        if lower == "::1" || lower == "0.0.0.0" || lower == "::" { return true }
        if lower.hasPrefix("fe80:") || lower.hasPrefix("fc") || lower.hasPrefix("fd") { return true }
        let parts = lower.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        switch (parts[0], parts[1]) {
        case (127, _), (10, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        default: return false
        }
    }

    /// `lsof -F pcn` çıktısını çözer. Yalnızca dış uzak adresi olan süreçler döner.
    static func parse(_ output: String) -> [ProcessConnections] {
        var pid: Int32?
        var name = ""
        var remotes: [Int32: [String]] = [:]
        var names: [Int32: String] = [:]
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": pid = Int32(value); name = ""
            case "c": name = value; if let pid { names[pid] = value }
            case "n":
                guard let pid, let arrow = value.range(of: "->"),
                      let remote = splitEndpoint(String(value[arrow.upperBound...])),
                      !isLocalHost(remote.host) else { continue }
                remotes[pid, default: []].append("\(remote.host):\(remote.port)")
            default: break
            }
        }
        return remotes.map { pid, list in
            var tally: [String: Int] = [:]
            for item in list { tally[item, default: 0] += 1 }
            let ordered = tally.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
            return ProcessConnections(pid: pid, process: names[pid] ?? L("bilinmeyen"), remotes: ordered, count: list.count)
        }
        .sorted { $0.count == $1.count ? $0.pid < $1.pid : $0.count > $1.count }
    }

    /// `lsof` yoksa veya 8 saniyede bitmezse boş döner. Yetkisiz kullanıcı yalnızca kendi süreçlerini görür.
    nonisolated static func scan() -> [ProcessConnections] {
        let path = "/usr/sbin/lsof"
        guard FileManager.default.isExecutableFile(atPath: path) else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-nP", "-iTCP", "-sTCP:ESTABLISHED", "-F", "pcn"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return parse(String(decoding: data, as: UTF8.self))
    }
}

@MainActor
final class ConnectionModel: ObservableObject {
    @Published private(set) var items: [ProcessConnections] = []
    @Published private(set) var loading = false
    @Published private(set) var loaded = false

    func reload() {
        guard !loading else { return }
        loading = true
        Task {
            items = await Task.detached { ConnectionScan.scan() }.value
            loading = false
            loaded = true
        }
    }
}

/// Araçlar sayfasında hangi sürecin hangi dış adrese bağlı olduğunu gösterir. Salt okunur.
struct ConnectionCard: View {
    @StateObject private var model = ConnectionModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardHeader(symbol: "arrow.left.arrow.right", title: "Dış bağlantılar",
                           trailing: model.loaded ? L("%ld süreç", model.items.count) : "")
                if model.loading { ProgressView().controlSize(.small) }
                Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .glassButton()
                    .controlSize(.small)
                    .disabled(model.loading)
                    .help("Yeniden tara")
                    .accessibilityLabel("Yeniden tara")
            }
            if model.items.isEmpty {
                Text(model.loaded ? L("Dış bağlantı bulunamadı.") : L("Taranıyor...")).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(model.items.prefix(12)) { item in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.process).font(.caption).lineLimit(1)
                            Text(verbatim: item.remotes.prefix(2).joined(separator: ", ") + (item.remotes.count > 2 ? " +\(item.remotes.count - 2)" : ""))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 6)
                        Text("\(item.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                if model.items.count > 12 {
                    Text(L("%ld süreç daha var.", model.items.count - 12)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text("Yalnızca kurulu TCP bağlantıları listelenir. Adresler bu Mac'ten çıkmaz, ülke sorgusu yapılmaz. Yönetici yetkisi olmadan yalnızca sizin süreçleriniz görünür. MoleBar bağlantıyı engellemez.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .onAppear { if !model.loaded { model.reload() } }
    }
}
