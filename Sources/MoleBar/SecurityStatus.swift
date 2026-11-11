import AppKit
import SwiftUI

/// Temel güvenlik ayarlarının durumu. Yalnızca okur. MoleBar hiçbir ayarı değiştirmez.
enum SecurityCheck {
    enum State: Equatable {
        case on, off, unknown
        var needsAttention: Bool { self == .off }
    }

    enum Setting: CaseIterable {
        case fileVault, gatekeeper, firewall, sip

        var title: String {
            switch self {
            case .fileVault: return L("FileVault (disk şifreleme)")
            case .gatekeeper: return L("Gatekeeper (uygulama denetimi)")
            case .firewall: return L("Güvenlik duvarı")
            case .sip: return L("SIP (sistem bütünlüğü koruması)")
            }
        }

        var command: (path: String, arguments: [String]) {
            switch self {
            case .fileVault: return ("/usr/bin/fdesetup", ["status"])
            case .gatekeeper: return ("/usr/sbin/spctl", ["--status"])
            case .firewall: return ("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"])
            case .sip: return ("/usr/bin/csrutil", ["status"])
            }
        }

        /// Ayar kapalıysa kullanıcıya gösterilen yol. MoleBar bunu uygulamaz.
        var hint: String {
            switch self {
            case .fileVault: return L("Sistem Ayarları > Gizlilik ve Güvenlik > FileVault'tan açın.")
            case .gatekeeper: return L("Terminal'de `sudo spctl --master-enable` çalıştırın.")
            case .firewall: return L("Sistem Ayarları > Ağ > Güvenlik Duvarı'ndan açın.")
            case .sip: return L("Kurtarma modunda `csrutil enable` çalıştırın.")
            }
        }
    }

    /// Komut çıktısını duruma çevirir. Tanınmayan çıktı `unknown` olur, kapalı sayılmaz.
    static func parse(_ setting: Setting, output: String) -> State {
        let text = output.lowercased()
        func decide(on: String, off: String) -> State {
            if text.contains(off) { return .off }
            return text.contains(on) ? .on : .unknown
        }
        switch setting {
        case .fileVault: return decide(on: "filevault is on", off: "filevault is off")
        case .gatekeeper: return decide(on: "assessments enabled", off: "assessments disabled")
        case .firewall: return decide(on: "firewall is enabled", off: "firewall is disabled")
        case .sip:
            if text.contains("custom configuration") { return .unknown }
            return decide(on: "status: enabled", off: "status: disabled")
        }
    }

    /// Komutu çalıştırır. 5 saniyede bitmezse veya çalışmazsa `unknown` döner.
    nonisolated static func run(_ setting: Setting) -> State {
        let command = setting.command
        guard FileManager.default.isExecutableFile(atPath: command.path) else { return .unknown }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.path)
        process.arguments = command.arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return .unknown }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return parse(setting, output: String(decoding: data, as: UTF8.self))
    }
}

@MainActor
final class SecurityModel: ObservableObject {
    @Published private(set) var states: [SecurityCheck.Setting: SecurityCheck.State] = [:]
    @Published private(set) var loaded = false

    func reload() {
        Task {
            let result = await Task.detached { () -> [SecurityCheck.Setting: SecurityCheck.State] in
                var map: [SecurityCheck.Setting: SecurityCheck.State] = [:]
                for setting in SecurityCheck.Setting.allCases { map[setting] = SecurityCheck.run(setting) }
                return map
            }.value
            states = result
            loaded = true
        }
    }
}

/// Araçlar sayfasında güvenlik özeti. Salt okunur.
struct SecurityCard: View {
    @StateObject private var model = SecurityModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "lock.shield", title: "Güvenlik özeti", trailing: attentionCount == 0 ? "" : L("%ld uyarı", attentionCount))
            if !model.loaded {
                Text("Okunuyor...").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(SecurityCheck.Setting.allCases, id: \.title) { setting in
                    let state = model.states[setting] ?? .unknown
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(setting.title).font(.subheadline)
                            Spacer(minLength: 8)
                            Text(label(state)).font(.caption.weight(.semibold)).foregroundStyle(color(state))
                        }
                        if state.needsAttention {
                            Text(setting.hint).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Button("Gizlilik ve Güvenlik ayarlarını aç") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .glassButton()
                .controlSize(.small)
                Text("MoleBar bu ayarları değiştirmez. Okunamayan ayar kapalı sayılmaz.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .onAppear { if !model.loaded { model.reload() } }
    }

    private var attentionCount: Int { model.states.values.filter(\.needsAttention).count }

    private func label(_ state: SecurityCheck.State) -> String {
        switch state {
        case .on: return L("Etkin")
        case .off: return L("Kapalı")
        case .unknown: return L("Okunamadı")
        }
    }

    private func color(_ state: SecurityCheck.State) -> Color {
        switch state {
        case .on: return .green
        case .off: return .orange
        case .unknown: return .secondary
        }
    }
}
