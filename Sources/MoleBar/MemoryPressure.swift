import Foundation

/// macOS bellek baskısı düzeyi. Etkinlik Monitörü'ndeki yeşil, sarı ve kırmızı grafikle aynı kaynaktır.
enum MemoryPressure: Equatable {
    case normal, warning, critical

    /// `kern.memorystatus_vm_pressure_level` değeri: 1 normal, 2 uyarı, 4 kritik. Tanımsız değer normal sayılır.
    init(level: Int) {
        switch level {
        case 2: self = .warning
        case 4: self = .critical
        default: self = .normal
        }
    }

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Uyarı"
        case .critical: return "Kritik"
        }
    }

    var needsAttention: Bool { self != .normal }

    static func sample() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        return MemoryPressure(level: Int(level))
    }
}

/// Takas (swap) kullanımı. Salt okunur.
struct SwapUsage: Equatable {
    var usedBytes: UInt64
    var totalBytes: UInt64
    var percent: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) * 100 }

    static func sample() -> SwapUsage {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return SwapUsage(usedBytes: 0, totalBytes: 0) }
        return SwapUsage(usedBytes: usage.xsu_used, totalBytes: usage.xsu_total)
    }
}
