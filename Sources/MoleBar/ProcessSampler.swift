import Foundation
import Darwin

/// Aynı uygulamanın süreçleri tek satırda toplanır (örn. tarayıcı yardımcı süreçleri).
struct ProcessGroup: Identifiable {
    let name: String
    var pids: [Int32]
    var cpu: Double
    var memoryBytes: UInt64
    var killable: Bool
    var id: String { name }

    func terminate() {
        for pid in pids { kill(pid, SIGTERM) }
    }
}

/// libproc ile süreç CPU ve bellek örnekleri. CPU yüzdesi tick farkından hesaplanır
/// (çok çekirdekli süreçte %100 üstü olabilir).
struct ProcessSampler {
    private var previousTicks: [Int32: UInt64] = [:]
    private var previousDate = Date()
    private var timebase = mach_timebase_info_data_t()

    private static let protectedNames: Set<String> = [
        "launchd", "kernel_task", "WindowServer", "loginwindow",
        "Dock", "Finder", "SystemUIServer", "MoleBar"
    ]

    init() { mach_timebase_info(&timebase) }

    mutating func sample() -> [ProcessGroup] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        var pids = [Int32](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<Int32>.stride)))
        guard count > 0 else { return [] }

        let now = Date()
        let wallNs = max(now.timeIntervalSince(previousDate), 0.001) * 1_000_000_000
        let taskSize = Int32(MemoryLayout<proc_taskinfo>.stride)
        let ownPid = getpid()
        var pathBuffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        var ticksNow: [Int32: UInt64] = [:]
        var groups: [String: ProcessGroup] = [:]

        for pid in pids.prefix(count) where pid > 0 {
            var info = proc_taskinfo()
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, taskSize) == taskSize else { continue }
            let ticks = info.pti_total_user &+ info.pti_total_system
            ticksNow[pid] = ticks

            var cpu = 0.0
            if let before = previousTicks[pid], ticks >= before {
                let deltaNs = Double(ticks - before) * Double(timebase.numer) / Double(timebase.denom)
                cpu = deltaNs / wallNs * 100
            }

            guard proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 else { continue }
            let name = Self.displayName(String(cString: pathBuffer))

            var group = groups[name] ?? ProcessGroup(
                name: name, pids: [], cpu: 0, memoryBytes: 0,
                killable: !Self.protectedNames.contains(name)
            )
            group.pids.append(pid)
            group.cpu += cpu
            group.memoryBytes += info.pti_resident_size
            if group.killable && (pid == ownPid || kill(pid, 0) != 0) { group.killable = false }
            groups[name] = group
        }

        previousTicks = ticksNow
        previousDate = now
        return Array(groups.values)
    }

    private static func displayName(_ path: String) -> String {
        if let range = path.range(of: ".app/") {
            return URL(fileURLWithPath: String(path[..<range.lowerBound])).lastPathComponent
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}
