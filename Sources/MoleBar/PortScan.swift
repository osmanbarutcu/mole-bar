import SwiftUI

struct ListeningPort: Identifiable, Equatable {
    enum Scope: Int, Comparable {
        case all, interface, local

        var label: String {
            switch self {
            case .all: return L("Tüm ağa açık")
            case .interface: return L("Ağ arayüzü")
            case .local: return L("Yerel")
            }
        }

        static func < (lhs: Scope, rhs: Scope) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let pid: Int
    let process: String
    let address: String
    let port: Int
    let scope: Scope
    var id: String { "\(pid)/\(port)/\(scope.rawValue)" }

    /// Satır altı metni. PID ve port kimliktir, binlik ayraç almaz.
    /// `Text("\(sayı)")` tamsayıyı yerel ayara göre biçimler (8001 → 8.001). Bu yüzden düz String kurulur.
    var detail: String { "PID \(pid) · \(address):\(port)" }
}

/// Dinleyen TCP portlarını listeler. Yalnızca `lsof` çıktısını okur. MoleBar hiçbir süreci kapatmaz.
enum PortScan {
    private static let wildcards: Set<String> = ["*", "0.0.0.0", "::"]

    /// `lsof -F pcn` çıktısını ayrıştırır. Aynı süreç ve portun IPv4 ve IPv6 kayıtları tek satıra iner.
    /// En geniş erişim önce gelir, sonra port sırası.
    static func parse(_ output: String) -> [ListeningPort] {
        var pid: Int?
        var process = ""
        var seen = Set<String>()
        var result: [ListeningPort] = []
        for line in output.split(whereSeparator: \.isNewline) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                pid = Int(value)
                process = ""
            case "c":
                process = value.replacingOccurrences(of: "\\x20", with: " ")
            case "n":
                guard let pid, let entry = endpoint(value) else { continue }
                let port = ListeningPort(pid: pid, process: process, address: entry.host, port: entry.port, scope: scope(of: entry.host))
                if seen.insert(port.id).inserted { result.append(port) }
            default:
                continue
            }
        }
        return result.sorted { ($0.scope, $0.port, $0.pid) < ($1.scope, $1.port, $1.pid) }
    }

    static func exposedCount(_ ports: [ListeningPort]) -> Int { ports.filter { $0.scope == .all }.count }

    /// "*:7000", "127.0.0.1:11434", "[::1]:3000". Port sayı değilse nil döner.
    private static func endpoint(_ text: String) -> (host: String, port: Int)? {
        guard let colon = text.lastIndex(of: ":"), let port = Int(text[text.index(after: colon)...]) else { return nil }
        var host = String(text[..<colon])
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        return host.isEmpty ? nil : (host, port)
    }

    private static func scope(of host: String) -> ListeningPort.Scope {
        if wildcards.contains(host) { return .all }
        if host == "::1" || host.hasPrefix("127.") { return .local }
        return .interface
    }

    /// `lsof` yoksa veya 8 saniyede bitmezse boş döner.
    nonisolated static func scan() -> [ListeningPort] {
        let path = "/usr/sbin/lsof"
        guard FileManager.default.isExecutableFile(atPath: path) else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"]
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
final class PortScanModel: ObservableObject {
    @Published private(set) var ports: [ListeningPort] = []
    @Published private(set) var loading = false
    @Published private(set) var loaded = false

    func reload() {
        guard !loading else { return }
        loading = true
        Task {
            ports = await Task.detached { PortScan.scan() }.value
            loading = false
            loaded = true
        }
    }
}

/// Araçlar sayfasında açık dinleme portları. Salt okunur.
struct PortScanCard: View {
    @StateObject private var model = PortScanModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardHeader(symbol: "network", title: "Açık portlar", trailing: trailing)
                if model.loading { ProgressView().controlSize(.small) }
                Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .glassButton()
                    .controlSize(.small)
                    .disabled(model.loading)
                    .help("Yeniden tara")
                    .accessibilityLabel("Yeniden tara")
            }
            if model.ports.isEmpty {
                Text(model.loaded ? L("Dinleyen port bulunamadı.") : L("Taranıyor...")).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(model.ports) { port in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(port.process.isEmpty ? L("bilinmeyen") : port.process).font(.caption).lineLimit(1)
                            Text(verbatim: port.detail).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 6)
                        Text(port.scope.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(port.scope == .all ? Color.orange : Color.secondary)
                    }
                }
            }
            Text("Tüm ağa açık: bağlı her ağdan erişilir. Yerel: yalnızca bu Mac. Yönetici yetkisi olmadan yalnızca sizin süreçleriniz görünür. MoleBar süreçleri kapatmaz.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .onAppear { if !model.loaded { model.reload() } }
    }

    private var trailing: String {
        guard model.loaded else { return "" }
        let exposed = PortScan.exposedCount(model.ports)
        return L("%ld port", model.ports.count) + (exposed > 0 ? " · " + L("%ld tüm ağa açık", exposed) : "")
    }
}
