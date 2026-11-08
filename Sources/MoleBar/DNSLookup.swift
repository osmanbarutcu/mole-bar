import SwiftUI

/// Sistem çözümleyicisinden alan adı sorgusu. `dscacheutil -q host -a name <ad>` komutunun karşılığıdır.
enum DNSLookup {
    struct Result: Equatable {
        let name: String
        let ipv4: [String]
        let ipv6: [String]
        var isEmpty: Bool { ipv4.isEmpty && ipv6.isEmpty }
    }

    /// Komuta yalnızca geçerli alan adı verilir. Başta `-` olan değer komut seçeneği sayılırdı, bu yüzden reddedilir.
    static func isValidHostname(_ text: String) -> Bool {
        var name = text
        if name.hasSuffix(".") { name.removeLast() }
        guard (1...253).contains(name.count) else { return false }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        return name.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            (1...63).contains(label.count) && label.allSatisfy(allowed.contains)
                && !label.hasPrefix("-") && !label.hasSuffix("-")
        }
    }

    /// `ip_address:` ve `ipv6_address:` satırlarını okur. Kopya adres düşer.
    static func parse(_ output: String, fallbackName: String) -> Result {
        var name = fallbackName
        var v4: [String] = []
        var v6: [String] = []
        for line in output.split(whereSeparator: \.isNewline) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }
            switch key {
            case "name" where name == fallbackName: name = value
            case "ip_address" where !v4.contains(value): v4.append(value)
            case "ipv6_address" where !v6.contains(value): v6.append(value)
            default: continue
            }
        }
        return Result(name: name, ipv4: v4, ipv6: v6)
    }

    /// Komut yoksa veya 8 sn'de bitmezse nil döner. Kabuk kullanılmaz, ad tek argümandır.
    nonisolated static func lookup(_ host: String) -> Result? {
        let path = "/usr/bin/dscacheutil"
        guard isValidHostname(host), FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-q", "host", "-a", "name", host]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        guard process.terminationStatus == 0 else { return nil }
        return parse(String(decoding: data, as: UTF8.self), fallbackName: host)
    }
}

@MainActor
final class DNSLookupModel: ObservableObject {
    enum State: Equatable {
        case idle, running, invalid, failed
        case result(DNSLookup.Result)
    }

    @Published var host = ""
    @Published private(set) var state: State = .idle
    @Published private(set) var note: String?

    /// `flushFirst` açıksa önce DNS önbelleği temizlenir. Parola penceresi iptal edilirse sorgu yapılmaz.
    func lookup(flushFirst: Bool, maintenance: MaintenanceModel) {
        let name = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DNSLookup.isValidHostname(name) else { state = .invalid; note = nil; return }
        guard state != .running else { return }
        state = .running
        note = nil
        Task {
            if flushFirst {
                let outcome = await maintenance.run(.flushDNS)
                guard outcome == .success else {
                    state = .idle
                    note = maintenance.messages[.flushDNS]
                    return
                }
                note = MaintenanceAction.flushDNS.doneText
            }
            let result = await Task.detached { DNSLookup.lookup(name) }.value
            state = result.map { .result($0) } ?? .failed
        }
    }
}

/// Araçlar sayfasında alan adı sorgusu.
struct DNSLookupCard: View {
    @StateObject private var model = DNSLookupModel()
    @StateObject private var maintenance = MaintenanceModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "magnifyingglass", title: "DNS sorgusu")
            HStack(spacing: 8) {
                TextField("alan.adi.com", text: $model.host)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .autocorrectionDisabled()
                    .onSubmit { model.lookup(flushFirst: false, maintenance: maintenance) }
                Button("Sorgula") { model.lookup(flushFirst: false, maintenance: maintenance) }
                    .glassButton()
                    .controlSize(.small)
                    .disabled(model.state == .running)
            }
            Button("Önbelleği temizle ve sorgula") { model.lookup(flushFirst: true, maintenance: maintenance) }
                .glassButton()
                .controlSize(.small)
                .disabled(model.state == .running)
            if let note = model.note {
                Text(note).font(.caption2).foregroundStyle(.secondary)
            }
            stateView
            Text("Sorgu sistemin çözümleyicisiyle yapılır (dscacheutil -q host). /etc/hosts kayıtları ve önbellek de sonuca girer.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    @ViewBuilder
    private var stateView: some View {
        switch model.state {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Sorgulanıyor...").font(.caption).foregroundStyle(.secondary)
            }
        case .invalid:
            Text("Geçersiz alan adı. Harf, rakam, tire ve nokta kullanın.").font(.caption).foregroundStyle(.secondary)
        case .failed:
            Text("Sorgu çalışmadı.").font(.caption).foregroundStyle(.secondary)
        case .result(let result):
            if result.isEmpty {
                Text("\(result.name) çözümlenemedi.").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: result.name).font(.caption)
                    ForEach(result.ipv4 + result.ipv6, id: \.self) { address in
                        Text(verbatim: address)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
    }
}
