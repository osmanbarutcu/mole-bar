import Foundation
import IOKit.ps
import IOKit
import SwiftUI

struct BatteryInfo: Equatable {
    var percent: Int
    var isCharging: Bool
    var onACPower: Bool
    var minutesRemaining: Int?
    var cycleCount: Int?
}

struct SystemInfo: Equatable {
    var battery: BatteryInfo?
    var thermal: ProcessInfo.ThermalState
    var uptime: TimeInterval

    static let rebootHintDays = 30

    static func sample() -> SystemInfo {
        SystemInfo(battery: readBattery(), thermal: ProcessInfo.processInfo.thermalState, uptime: readUptime())
    }

    /// Açılıştan beri geçen süre. Uyku süresi dahildir (kern.boottime).
    static func readUptime(now: Date = Date()) -> TimeInterval {
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return ProcessInfo.processInfo.systemUptime }
        return now.timeIntervalSince1970 - Double(boot.tv_sec)
    }

    static func readBattery() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let percent = info[kIOPSCurrentCapacityKey] as? Int else { continue }
            let remaining = info[kIOPSTimeToEmptyKey] as? Int
            return BatteryInfo(
                percent: percent,
                isCharging: info[kIOPSIsChargingKey] as? Bool ?? false,
                onACPower: info[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                minutesRemaining: (remaining ?? -1) > 0 ? remaining : nil,
                cycleCount: readCycleCount()
            )
        }
        return nil
    }

    private static func readCycleCount() -> Int? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "CycleCount" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Int
    }

    // MARK: Metinler

    static func uptimeText(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        if days > 0 { return "\(days) gün \(hours) saat" }
        let minutes = (total % 3_600) / 60
        return hours > 0 ? "\(hours) saat \(minutes) dk" : "\(minutes) dk"
    }

    static func thermalText(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Normal"
        case .fair: return "Hafif yüksek"
        case .serious: return "Yüksek"
        case .critical: return "Kritik"
        @unknown default: return "Bilinmiyor"
        }
    }

    static func batteryText(_ battery: BatteryInfo) -> String {
        var text = "%\(battery.percent)"
        if battery.isCharging { text += " · şarj oluyor" }
        else if battery.onACPower { text += " · şarjda" }
        else if let minutes = battery.minutesRemaining { text += " · \(minutes / 60) sa \(minutes % 60) dk kaldı" }
        else { text += " · pilde" }
        return text
    }

    var needsReboot: Bool { uptime >= Double(Self.rebootHintDays) * 86_400 }
}

struct SystemInfoCard: View {
    let info: SystemInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "macbook", title: "Sistem")
            if let battery = info.battery {
                row("battery.100", "Pil", SystemInfo.batteryText(battery) + (battery.cycleCount.map { " · \($0) döngü" } ?? ""))
            }
            row("thermometer.medium", "Isı durumu", SystemInfo.thermalText(info.thermal))
            row("clock", "Açık kalma", SystemInfo.uptimeText(info.uptime))
            if info.needsReboot {
                Text("Mac \(SystemInfo.rebootHintDays) günden uzun süredir açık. Yeniden başlatmak belleği ve geçici dosyaları temizler.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func row(_ symbol: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(.secondary)
            Text(title).font(.subheadline)
            Spacer(minLength: 8)
            Text(value).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}
