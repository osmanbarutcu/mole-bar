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
    @Published var disk = DiskSnapshot(usedBytes: 0, totalBytes: 0)
    @Published var netDown: Double = 0
    @Published var netUp: Double = 0
    @Published var diskRead: Double = 0
    @Published var diskWrite: Double = 0
    @Published var volumes: [VolumeInfo] = []
    @Published var processGroups: [ProcessGroup] = []
    @Published var health: MoleHealth?
    @Published var diskAlert = false
    /// Son 1 saat, 30 saniyelik örnek (en çok 120 nokta). Yalnızca bellekte tutulur.
    @Published var history: [HistoryPoint] = []

    let cleanPreview = CleanPreview()
    /// Panel ve ana pencere aynı önbellek modelini paylaşır.
    let cacheCleaner = CacheCleaner()
    private var procSampler = ProcessSampler()
    private var healthLoading = false
    private var diskNotified = false
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
        if tick % 15 == 1 { refreshHealth() }
        if tick == 30 || tick % 900 == 0 { cleanPreview.startIfDue() }
        let cpuResult = cpu.sample()
        cpuTotal = cpuResult.total
        cpuPerCore = cpuResult.perCore
        memory = sampleMemory()
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
