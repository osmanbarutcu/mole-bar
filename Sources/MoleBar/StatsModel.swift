import Foundation
import SwiftUI

@MainActor
final class StatsModel: ObservableObject {
    /// Uygulama genelinde tek örnek. Menü çubuğu paneli, ana pencere ve özel durum çubuğu öğesi aynı ölçümleri paylaşır.
    static let shared = StatsModel()

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
    /// Kurulu sürümden yeni bir sürüm varsa dolar. Denetim kapalıysa nil kalır.
    @Published var availableUpdate: ReleaseInfo?
    private var updateChecking = false
    private var sensorsLoading = false
    /// Süreç başına ağ hızı (bayt/sn). Yalnızca Süreçler sayfası "Ağ" sıralamasındayken güncellenir.
    @Published var netByPid: [Int32: Double] = [:]
    private var netLoading = false
    @Published var diskAlert = false
    /// Son 7 gün, 30 saniyelik örnek. `MetricStore` dosyasından yüklenir ve her örnekte dosyaya eklenir.
    @Published private(set) var longHistory: [MetricSample] = []
    private let metricStore = MetricStore.shared
    /// Geçmiş dosyasına yapılan son iş. Yükleme, ekleme ve sıkıştırma bu zincirle sırayla çalışır.
    /// Sıkıştırma dosyayı yeniden yazar. Aynı anda yapılan ekleme kaybolmasın diye işler birbirini bekler.
    private var historyWrite: Task<Void, Never>?
    private var samplesSinceCompact = 0
    /// Günde bir sıkıştırma: 30 saniyelik 2880 örnek.
    private let compactEvery = 2_880
    /// Menü çubuğu grafiği için son 30 CPU örneği. Her turda bir örnek alınır.
    @Published private(set) var recentCPU: [Double] = []
    @Published private(set) var recentRAM: [Double] = []
    /// İndirme ve yükleme toplamı, bayt/sn.
    @Published private(set) var recentNet: [Double] = []

    func recent(_ metric: GraphMetric) -> [Double] {
        switch metric {
        case .cpu: return recentCPU
        case .ram: return recentRAM
        case .net: return recentNet
        }
    }

    let cleanPreview = CleanPreview()
    /// Panel ve ana pencere aynı önbellek modelini paylaşır.
    let cacheCleaner = CacheCleaner()
    private var procSampler = ProcessSampler()
    private var healthLoading = false
    private var diskNotified = false
    private var memoryAlert = MemoryAlert()
    private var cpuHogAlert = CPUHogAlert()
    private var tick = 0
    private var cpu = CPUSampler()
    private var network = NetworkSampler()
    private var diskIO = DiskIOSampler()
    private var timer: Timer?
    private let interval: TimeInterval = 2

    init() {
        let store = metricStore
        historyWrite = Task {
            let loaded = await Task.detached(priority: .utility) { store.load() }.value
            // Yükleme sürerken alınan örnekler kaybolmaz.
            longHistory = loaded + longHistory.filter { sample in sample.time > (loaded.last?.time ?? .distantPast) }
        }
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
        if tick % 2 == 0 {
            processGroups = procSampler.sample()
            evaluateCPUHogs()
        }
        if tick % 15 == 1 { refreshHealth(); systemInfo = SystemInfo.sample() }
        if tick % 5 == 1 { refreshSensors() }
        if tick == 45 || tick % 1800 == 0 { checkForUpdateIfDue() }
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
        let memoryAlertEnabled = UserDefaults.standard.object(forKey: "memoryAlertEnabled") as? Bool ?? true
        if memoryAlertEnabled, memoryAlert.shouldNotify(pressure) {
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
        recentRAM = MenuBarGraph.push(recentRAM, memory.percent, limit: 30)
        recentNet = MenuBarGraph.push(recentNet, net.down + net.up, limit: 30)
        let io = diskIO.sample()
        diskRead = io.read
        diskWrite = io.write
        evaluateDiskAlert()
        if tick % 15 == 1 { DiskLog.record(disk) }
        // İlk turda CPU yüzdesi 0 ve süreç listesi boştur. Kayıt 30 saniyede bir, ilk tur atlanarak alınır.
        if tick % 15 == 0 { recordLongHistory() }
    }

    private func evaluateCPUHogs() {
        guard UserDefaults.standard.object(forKey: "cpuAlertEnabled") as? Bool ?? true else { return }
        let names = cpuHogAlert.evaluate(processGroups.map { ($0.name, $0.cpu) }, now: Date())
        guard !names.isEmpty else { return }
        DiskNotifier.post(title: "Yüksek CPU kullanımı", body: CPUHogAlert.body(for: names), id: "molebar.cpu")
    }

    /// Örneği belleğe ve dosyaya ekler. Dosya yazımı ana iş parçacığını bekletmez.
    private func recordLongHistory() {
        let sample = MetricSample(
            time: Date(),
            cpu: cpuTotal,
            memory: memory.percent,
            disk: disk.percent,
            topCPU: processGroups.max { $0.cpu < $1.cpu }?.name,
            topMemory: processGroups.max { $0.memoryBytes < $1.memoryBytes }?.name
        )
        longHistory = MetricHistory.prune(longHistory + [sample], now: sample.time, maxAge: MetricHistory.maxAge)
        samplesSinceCompact += 1
        let compact = samplesSinceCompact >= compactEvery
        if compact { samplesSinceCompact = 0 }
        let store = metricStore
        let previous = historyWrite
        historyWrite = Task {
            await previous?.value
            await Task.detached(priority: .utility) {
                store.append(sample)
                if compact { _ = store.load() }
            }.value
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

    /// Ayarlarda açıksa ve son denetimden 24 saat geçtiyse GitHub'a bir istek gönderir.
    func checkForUpdateIfDue() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: UpdateCheck.enabledKey), !updateChecking,
              UpdateCheck.isDue(lastCheck: defaults.object(forKey: UpdateCheck.lastCheckKey) as? Date) else { return }
        updateChecking = true
        Task {
            let latest = await UpdateCheck.fetchLatest()
            updateChecking = false
            guard let latest else { return }
            defaults.set(Date(), forKey: UpdateCheck.lastCheckKey)
            guard UpdateCheck.isNewer(latest.version, than: UpdateCheck.currentVersion) else {
                availableUpdate = nil
                return
            }
            if availableUpdate?.version != latest.version {
                DiskNotifier.post(
                    title: "MoleBar \(latest.version) çıktı",
                    body: "Kurulu sürüm \(UpdateCheck.currentVersion). Sürüm sayfası Ayarlar'da.",
                    id: "molebar.update"
                )
            }
            availableUpdate = latest
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
