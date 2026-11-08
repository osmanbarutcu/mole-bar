import SwiftUI

/// Yönetici parolası isteyen ağ ve önbellek bakımı işleri. Komutlar sabittir, kullanıcı girdisi içermez.
enum MaintenanceAction: String, CaseIterable, Identifiable {
    case flushDNS, flushARP, purgeMemory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flushDNS: "DNS önbelleğini temizle"
        case .flushARP: "ARP tablosunu temizle"
        case .purgeMemory: "Bellek önbelleğini boşalt"
        }
    }

    var detail: String {
        switch self {
        case .flushDNS: "Eski alan adı kayıtlarını siler. DNS değiştirdiyseniz kullanın."
        case .flushARP: "Yerel ağ cihaz eşlemelerini siler. Ağ cihazı görünmüyorsa kullanın. Bağlantı bir an kesilebilir."
        case .purgeMemory: "Disk önbelleğini boşaltır. Mac kısa süre yavaşlayabilir."
        }
    }

    var symbol: String {
        switch self {
        case .flushDNS: "arrow.triangle.2.circlepath"
        case .flushARP: "point.3.connected.trianglepath.dotted"
        case .purgeMemory: "memorychip"
        }
    }

    /// Yönetici yetkisiyle çalışan sabit komut.
    var command: String {
        switch self {
        case .flushDNS: "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder"
        case .flushARP: "/usr/sbin/arp -a -d"
        case .purgeMemory: "/usr/sbin/purge"
        }
    }

    var doneText: String {
        switch self {
        case .flushDNS: "DNS önbelleği temizlendi."
        case .flushARP: "ARP tablosu temizlendi."
        case .purgeMemory: "Bellek önbelleği boşaltıldı."
        }
    }
}

/// Komutu macOS'un kendi yönetici parolası penceresiyle çalıştırır. MoleBar parolayı görmez.
enum AdminCommand {
    enum Outcome: Equatable {
        case success, cancelled
        case failed(String)
    }

    /// `do shell script` metnini kurar. Ters eğik çizgi ve tırnak kaçırılır.
    static func script(for command: String) -> String {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }

    /// Kullanıcı pencereyi kapatırsa osascript `-128` hatası verir.
    static func classify(status: Int32, stderr: String) -> Outcome {
        if status == 0 { return .success }
        if stderr.contains("(-128)") { return .cancelled }
        let line = stderr.split(whereSeparator: \.isNewline).last.map(String.init) ?? "Bilinmeyen hata"
        return .failed(line)
    }

    /// Parola penceresi en çok 120 sn bekler.
    nonisolated static func run(_ action: MaintenanceAction) -> Outcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script(for: action.command)]
        let pipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return .failed("osascript başlatılamadı.") }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 120, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return classify(status: process.terminationStatus, stderr: String(decoding: data, as: UTF8.self))
    }
}

@MainActor
final class MaintenanceModel: ObservableObject {
    @Published private(set) var running: MaintenanceAction?
    @Published private(set) var messages: [MaintenanceAction: String] = [:]

    /// Sonucu döndürür. Başka bir iş sürüyorsa nil döner.
    @discardableResult
    func run(_ action: MaintenanceAction) async -> AdminCommand.Outcome? {
        guard running == nil else { return nil }
        running = action
        let outcome = await Task.detached { AdminCommand.run(action) }.value
        running = nil
        switch outcome {
        case .success: messages[action] = action.doneText
        case .cancelled: messages[action] = "İptal edildi."
        case .failed(let reason): messages[action] = "Başarısız: \(reason)"
        }
        return outcome
    }
}

/// Araçlar sayfasında ağ ve önbellek bakımı. Her iş macOS'un yönetici parolası penceresini açar.
struct NetworkMaintenanceCard: View {
    @StateObject private var model = MaintenanceModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "wrench.and.screwdriver", title: "Ağ ve önbellek bakımı")
            ForEach(MaintenanceAction.allCases) { action in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: action.symbol).frame(width: 22).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.title).font(.caption)
                        Text(action.detail).font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let message = model.messages[action] {
                            Text(message).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 6)
                    if model.running == action {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Çalıştır") { Task { await model.run(action) } }
                            .glassButton()
                            .controlSize(.small)
                            .disabled(model.running != nil)
                            .accessibilityLabel(action.title)
                    }
                }
            }
            Text("macOS yönetici parolanızı kendi penceresinde sorar. MoleBar parolayı görmez ve saklamaz.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
