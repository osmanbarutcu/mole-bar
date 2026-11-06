import Foundation
import SwiftUI

struct HistoryPoint {
    let cpu: Double
    let memory: Double
}

@MainActor
final class StatsModel: ObservableObject {
    @Published var cpuTotal: Double = 0
    @Published var cpuPerCore: [Double] = []
    @Published var memory = MemorySnapshot(usedBytes: 0, totalBytes: ProcessInfo.processInfo.physicalMemory)
    @Published var pressure = MemoryPressure.normal
    @Published var swap = SwapUsage(usedBytes: 0, totalBytes: 0)
    @Published var disk = DiskSnapshot(usedBytes: 0, totalBytes: 0)
    @Published var netDown: Double = 0
    @Published var netUp: Double = 0
    @Published var diskRead: Double = 0
    @Published var diskWrite: Double = 0
    @Published var volumes: [VolumeInfo] = []
    @Published var processGroups: [ProcessGroup] = []
    @Published var health: MoleHealth?
    @Published var systemInfo = SystemInfo.sample()
    /// Pil sağlığı yavaş değişir. Pil varsa uygulama açılışında bir kez okunur.
    @Published var batteryHealth: BatteryHealth?
    /// CPU/GPU sıcaklığı ve fan hızı (SMC, salt okunur). SMC açılamazsa nil kalır.
    @Published var sensors: SensorReading?
    private let smc = SMCReader()
    private var sensorsLoading = false
    /// Süreç başına ağ hızı (bayt/sn). Yalnızca Süreçler sayfası "Ağ" sıralamasındayken güncellenir.
    @Published var netByPid: [Int32: Double] = [:]
    private var netLoading = false
    @Published var diskAlert = false
    /// Son 1 saat, 30 saniyelik örnek (en çok 120 nokta). Yalnızca bellekte tutulur.
    @Published var history: [HistoryPoint] = []
    /// Menü çubuğu grafiği için son 30 CPU örneği. Her turda bir örnek alınır.
    @Published private(set) var recentCPU: [Double] = []

    let cleanPreview = CleanPreview()
    /// Panel ve ana pencere aynı önbellek modelini paylaşır.
    let cacheCleaner = CacheCleaner()
    private var procSampler = ProcessSampler()
    private var healthLoading = false
    private var diskNotified = false
    private var memoryAlert = MemoryAlert()
    private var tick = 0
    private var cpu = CPUSampler()
    private var network = NetworkSampler()
    private var diskIO = DiskIOSampler()
    private var timer: Timer?
    private let interval: TimeInterval = 2

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 0.2
    }

    deinit { timer?.invalidate() }

    func barText(cpu showCPU: Bool, ram showRAM: Bool, disk showDisk: Bool, labels: Bool) -> String {
        var parts: [String] = []
        if showCPU { parts.append(String(format: labels ? "CPU %.0f%%" : "%.0f%%", cpuTotal)) }
        if showRAM { parts.append(String(format: labels ? "RAM %.0f%%" : "%.0f%%", memory.percent)) }
        if showDisk { parts.append(String(format: labels ? "Disk %.0f%%" : "%.0f%%", disk.percent)) }
        return parts.isEmpty ? "MoleBar" : parts.joined(separator: " · ")
    }

    func refresh() {
        tick += 1
        if tick % 3 == 1 { volumes = sampleVolumes() }
        if tick % 2 == 0 { processGroups = procSampler.sample() }
        if tick % 15 == 1 { refreshHealth(); systemInfo = SystemInfo.sample() }
        if tick % 5 == 1 { refreshSensors() }
        if tick == 1, systemInfo.battery != nil {
            Task { batteryHealth = await Task.detached(priority: .utility) { BatteryHealth.fetch() }.value }
        }
        if tick % 3 == 0, UserDefaults.standard.string(forKey: "procSort") == "net" { refreshNet() }
        if tick == 30 || tick % 900 == 0 { cleanPreview.startIfDue() }
        let cpuResult = cpu.sample()
        cpuTotal = cpuResult.total
        recentCPU = MenuBarGraph.push(recentCPU, cpuResult.total, limit: 30)
        cpuPerCore = cpuResult.perCore
        memory = sampleMemory()
        pressure = MemoryPressure.sample()
        if memoryAlert.shouldNotify(pressure) {
            DiskNotifier.post(
                title: "Bellek baskısı kritik",
                body: "Mac belleği yetersiz kalıyor. Süreçler sayfasından büyük uygulamaları kapatın.",
                id: "molebar.memory"
            )
        }
        swap = SwapUsage.sample()
        disk = sampleDisk()
        let net = network.sample()
        netDown = net.down
        netUp = net.up
        let io = diskIO.sample()
        diskRead = io.read
        diskWrite = io.write
        evaluateDiskAlert()
        if tick % 15 == 1 { DiskLog.record(disk) }
        if tick % 15 == 1 {
            history.append(HistoryPoint(cpu: cpuTotal, memory: memory.percent))
            if history.count > 120 { history.removeFirst(history.count - 120) }
        }
    }

    private func refreshNet() {
        guard !netLoading else { return }
        netLoading = true
        Task {
            let result = await Task.detached(priority: .utility) { NetPerProcess.sample() }.value
            netByPid = result
            netLoading = false
        }
    }

    private func refreshSensors() {
        guard let smc, !sensorsLoading else { return }
        sensorsLoading = true
        Task {
            let reading = await Task.detached(priority: .utility) { smc.read() }.value
            sensors = reading.isEmpty ? nil : reading
            sensorsLoading = false
        }
    }

    /// Mole sağlık skorunu arka planda alır (yaklaşık 30 saniyede bir).
    private func refreshHealth() {
        guard MoleCLI.isInstalled, !healthLoading else { return }
        healthLoading = true
        Task {
            let result = await MoleCLI.fetchHealth()
            if let result { health = result }
            healthLoading = false
        }
    }

    /// Eşik aşımında bildirim bir kez gönderilir. Eşiğin 3 puan altına inince sıfırlanır.
    private func evaluateDiskAlert() {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: "diskAlertEnabled") as? Bool ?? true
        let stored = defaults.integer(forKey: "diskAlertThreshold")
        let limit = Double(stored == 0 ? 90 : stored)
        guard enabled else { diskAlert = false; return }
        if disk.percent >= limit {
            diskAlert = true
            if !diskNotified {
                diskNotified = true
                DiskNotifier.notify(percent: disk.percent)
            }
        } else if disk.percent < limit - 3 {
            diskAlert = false
            diskNotified = false
        }
    }
}

func formatBytes(_ bytes: UInt64) -> String {
    if bytes == 0 { return "0 KB" }
    return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
}

func formatRate(_ bytesPerSecond: Double) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .binary) + "/s"
}
