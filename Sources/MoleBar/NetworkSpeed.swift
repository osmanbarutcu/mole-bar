import SwiftUI

/// `networkQuality` ölçüm sonucu.
struct SpeedResult: Equatable {
    let downloadMbps: Double
    let uploadMbps: Double
    /// Dakikadaki gidiş-dönüş sayısı (RPM). Yüksek değer iyidir.
    let responsiveness: Int?
    let latencyMs: Double?

    /// Apple'ın eşikleri: 200 altı düşük, 1000 üstü yüksek.
    var responsivenessLabel: String? {
        guard let responsiveness else { return nil }
        switch responsiveness {
        case 1000...: return L("Yüksek")
        case 200...: return L("Orta")
        default: return L("Düşük")
        }
    }
}

/// Çalışan `networkQuality` sürecini iptal etmek için taşıyıcı.
final class SpeedRun: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    func attach(_ process: Process) {
        lock.withLock { self.process = process }
        if isCancelled { process.terminate() }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            if process?.isRunning == true { process?.terminate() }
        }
    }
}

/// Apple'ın `networkQuality` aracını çalıştırır. Araç Apple sunucularına bağlanır ve veri harcar.
enum NetworkSpeed {
    static let path = "/usr/bin/networkQuality"
    /// Ölçümün en uzun süresi (sn).
    static let maxSeconds = 15

    /// `-c` JSON çıktısını ayrıştırır. Hız bit/sn olarak gelir, Mb/sn'ye çevrilir.
    static func parse(_ data: Data) -> SpeedResult? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let down = (json["dl_throughput"] as? NSNumber)?.doubleValue,
              let up = (json["ul_throughput"] as? NSNumber)?.doubleValue else { return nil }
        return SpeedResult(downloadMbps: down / 1_000_000,
                           uploadMbps: up / 1_000_000,
                           responsiveness: (json["responsiveness"] as? NSNumber).map { Int($0.doubleValue.rounded()) },
                           latencyMs: (json["base_rtt"] as? NSNumber)?.doubleValue)
    }

    /// Araç yoksa, iptal edilirse veya bitmezse nil döner.
    nonisolated static func run(_ control: SpeedRun) -> SpeedResult? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-c", "-M", String(maxSeconds)]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        control.attach(process)
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + Double(maxSeconds) + 25, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        guard !control.isCancelled, process.terminationStatus == 0 else { return nil }
        return parse(data)
    }
}

@MainActor
final class SpeedModel: ObservableObject {
    enum State: Equatable {
        case idle, running
        case done(SpeedResult)
        case failed
    }

    @Published private(set) var state: State = .idle
    private var current: SpeedRun?

    func start() {
        guard state != .running else { return }
        state = .running
        let control = SpeedRun()
        current = control
        Task {
            let result = await Task.detached { NetworkSpeed.run(control) }.value
            guard !control.isCancelled else { return }
            state = result.map { .done($0) } ?? .failed
            current = nil
        }
    }

    func cancel() {
        current?.cancel()
        current = nil
        if state == .running { state = .idle }
    }
}

/// Araçlar sayfasında hız ve gecikme ölçümü. Yalnızca düğmeyle başlar.
struct NetworkSpeedCard: View {
    @StateObject private var model = SpeedModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardHeader(symbol: "speedometer", title: "Hız ve gecikme")
                if model.state == .running {
                    Button("İptal") { model.cancel() }.glassButton().controlSize(.small)
                } else {
                    Button("Ölç") { model.start() }.glassButton().controlSize(.small)
                }
            }
            switch model.state {
            case .idle:
                Text("Ölçülmedi.").font(.caption).foregroundStyle(.secondary)
            case .running:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("Ölçülüyor (en çok %ld sn)...", NetworkSpeed.maxSeconds)).font(.caption).foregroundStyle(.secondary)
                }
            case .failed:
                Text("Ölçüm tamamlanmadı. Bağlantıyı kontrol edin.").font(.caption).foregroundStyle(.secondary)
            case .done(let result):
                resultRows(result)
            }
            Text("Apple sunucularına bağlanır. Hat hızına göre yüzlerce MB veri harcar. Mobil bağlantıda dikkat edin.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .onDisappear { model.cancel() }
    }

    private func resultRows(_ result: SpeedResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            metric("arrow.down.circle", "İndirme", L("%.1f Mb/sn", result.downloadMbps))
            metric("arrow.up.circle", "Yükleme", L("%.1f Mb/sn", result.uploadMbps))
            if let latency = result.latencyMs { metric("timer", "Boşta gecikme", String(format: "%.0f ms", latency)) }
            if let rpm = result.responsiveness {
                metric("waveform.path.ecg", "Yanıt verme", "\(rpm) RPM" + (result.responsivenessLabel.map { " (\($0))" } ?? ""))
            }
        }
    }

    private func metric(_ symbol: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 22).foregroundStyle(.secondary)
            Text(L(title)).font(.caption)
            Spacer(minLength: 6)
            Text(verbatim: value).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}
