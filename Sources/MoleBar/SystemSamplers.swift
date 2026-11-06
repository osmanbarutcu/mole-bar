import Foundation
import IOKit

/// Çekirdek bazlı CPU kullanımı. host_processor_info tick farkından hesaplanır.
struct CPUSampler {
    private var previous: [[UInt32]] = []

    mutating func sample() -> (total: Double, perCore: [Double]) {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return (0, []) }
        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        let states = Int(CPU_STATE_MAX)
        var current: [[UInt32]] = []
        for core in 0..<Int(cpuCount) {
            let base = core * states
            current.append([
                UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])
            ])
        }
        defer { previous = current }
        guard previous.count == current.count else { return (0, Array(repeating: 0, count: current.count)) }

        var perCore: [Double] = []
        var busyTotal: UInt64 = 0
        var allTotal: UInt64 = 0
        for (now, before) in zip(current, previous) {
            let user = UInt64(now[0] &- before[0])
            let system = UInt64(now[1] &- before[1])
            let nice = UInt64(now[2] &- before[2])
            let idle = UInt64(now[3] &- before[3])
            let busy = user + system + nice
            let sum = busy + idle
            perCore.append(sum == 0 ? 0 : Double(busy) / Double(sum) * 100)
            busyTotal += busy
            allTotal += sum
        }
        let total = allTotal == 0 ? 0 : Double(busyTotal) / Double(allTotal) * 100
        return (total, perCore)
    }
}

struct MemorySnapshot {
    var usedBytes: UInt64
    var totalBytes: UInt64
    var percent: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) * 100 }
}

/// Etkinlik Monitörü ile aynı formül: uygulama + wired + sıkıştırılmış bellek.
func sampleMemory() -> MemorySnapshot {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
    let result = withUnsafeMutablePointer(to: &stats) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    let total = ProcessInfo.processInfo.physicalMemory
    guard result == KERN_SUCCESS else { return MemorySnapshot(usedBytes: 0, totalBytes: total) }

    var pageSize: vm_size_t = 0
    host_page_size(mach_host_self(), &pageSize)
    let appPages = UInt64(stats.internal_page_count) &- UInt64(stats.purgeable_count)
    let pages = appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
    return MemorySnapshot(usedBytes: pages * UInt64(pageSize), totalBytes: total)
}

struct DiskSnapshot {
    var usedBytes: UInt64
    var totalBytes: UInt64
    var percent: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) * 100 }
    var freeBytes: UInt64 { totalBytes &- usedBytes }
}

func sampleDisk(path: String = "/") -> DiskSnapshot {
    let url = URL(fileURLWithPath: path)
    let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]
    guard let values = try? url.resourceValues(forKeys: keys),
          let total = values.volumeTotalCapacity,
          let free = values.volumeAvailableCapacity else {
        return DiskSnapshot(usedBytes: 0, totalBytes: 0)
    }
    return DiskSnapshot(usedBytes: UInt64(max(total - free, 0)), totalBytes: UInt64(total))
}

struct VolumeInfo: Identifiable {
    var id: String { path }
    let path: String
    let name: String
    let usedBytes: UInt64
    let totalBytes: UInt64
    let isInternal: Bool
    var percent: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) * 100 }
    var freeBytes: UInt64 { totalBytes &- usedBytes }
}

/// Takılı yerel birimler. Gizli sistem birimleri ve ağ paylaşımları dışarıda kalır.
func sampleVolumes() -> [VolumeInfo] {
    let keys: [URLResourceKey] = [
        .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        .volumeIsInternalKey, .volumeIsLocalKey
    ]
    let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
    return urls.compactMap { url in
        guard let values = try? url.resourceValues(forKeys: Set(keys)),
              values.volumeIsLocal == true,
              let total = values.volumeTotalCapacity, total > 0,
              let free = values.volumeAvailableCapacity else { return nil }
        return VolumeInfo(
            path: url.path,
            name: values.volumeName ?? url.lastPathComponent,
            usedBytes: UInt64(max(total - free, 0)),
            totalBytes: UInt64(total),
            isInternal: values.volumeIsInternal ?? false
        )
    }
    .sorted { ($0.isInternal ? 0 : 1, $0.path) < ($1.isInternal ? 0 : 1, $1.path) }
}

/// Ağ sayaçları. 32 bit sayaç taşmasını &- ile karşılar.
struct NetworkSampler {
    private var previous: (rx: UInt32, tx: UInt32)?
    private var previousDate = Date()

    private func counters() -> (rx: UInt32, tx: UInt32) {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return (0, 0) }
        defer { freeifaddrs(head) }
        var rx: UInt32 = 0
        var tx: UInt32 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let name = String(cString: entry.pointee.ifa_name)
            if let address = entry.pointee.ifa_addr,
               address.pointee.sa_family == UInt8(AF_LINK),
               name.hasPrefix("en"),
               let data = entry.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                rx = rx &+ data.pointee.ifi_ibytes
                tx = tx &+ data.pointee.ifi_obytes
            }
            cursor = entry.pointee.ifa_next
        }
        return (rx, tx)
    }

    /// Bayt/sn cinsinden (indirme, yükleme).
    mutating func sample() -> (down: Double, up: Double) {
        let now = counters()
        let date = Date()
        defer { previous = now; previousDate = date }
        guard let before = previous else { return (0, 0) }
        let seconds = max(date.timeIntervalSince(previousDate), 0.001)
        return (Double(now.rx &- before.rx) / seconds, Double(now.tx &- before.tx) / seconds)
    }
}

/// Disk okuma/yazma sayaçları (IOBlockStorageDriver). Apple Silicon'da veri vermeyebilir; Doğrulanmadı.
struct DiskIOSampler {
    private var previous: (read: UInt64, write: UInt64)?
    private var previousDate = Date()

    private func counters() -> (read: UInt64, write: UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return (0, 0)
        }
        defer { IOObjectRelease(iterator) }
        var read: UInt64 = 0
        var write: UInt64 = 0
        while case let service = IOIteratorNext(iterator), service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let stats = dict["Statistics"] as? [String: Any] {
                read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                write += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(service)
        }
        return (read, write)
    }

    mutating func sample() -> (read: Double, write: Double) {
        let now = counters()
        let date = Date()
        defer { previous = now; previousDate = date }
        guard let before = previous else { return (0, 0) }
        let seconds = max(date.timeIntervalSince(previousDate), 0.001)
        return (Double(now.read &- before.read) / seconds, Double(now.write &- before.write) / seconds)
    }
}
