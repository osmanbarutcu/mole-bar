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
        if days > 0 { return L("%ld gün %ld saat", days, hours) }
        let minutes = (total % 3_600) / 60
        return hours > 0 ? L("%ld saat %ld dk", hours, minutes) : L("%ld dk", minutes)
    }

    static func thermalText(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return L("Normal")
        case .fair: return L("Hafif yüksek")
        case .serious: return L("Yüksek")
        case .critical: return L("Kritik")
        @unknown default: return L("Bilinmiyor")
        }
    }

    static func batteryText(_ battery: BatteryInfo) -> String {
        var text = L("%%%ld", battery.percent)
        if battery.isCharging { text += " · " + L("şarj oluyor") }
        else if battery.onACPower { text += " · " + L("şarjda") }
        else if let minutes = battery.minutesRemaining { text += " · " + L("%ld sa %ld dk kaldı", minutes / 60, minutes % 60) }
        else { text += " · " + L("pilde") }
        return text
    }

    var needsReboot: Bool { uptime >= Double(Self.rebootHintDays) * 86_400 }
}

struct SystemInfoCard: View {
    let info: SystemInfo
    var health: BatteryHealth?
    var sensors: SensorReading?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "macbook", title: "Sistem")
            if let battery = info.battery {
                row("battery.100", "Pil", SystemInfo.batteryText(battery) + (battery.cycleCount.map { " · " + L("%ld döngü", $0) } ?? ""))
            }
            if let health {
                row("heart.text.square", "Pil sağlığı", L("%%%ld kapasite · %@", health.maximumCapacity, health.condition))
                if health.needsAttention {
                    Text(L("Pil kapasitesi %%%ld altında. Apple bu düzeyde pil değişimini önerir.", BatteryHealth.attentionBelow))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            row("thermometer.medium", "Isı durumu", SystemInfo.thermalText(info.thermal))
            if let sensors {
                if let text = Self.temperatureText(sensors.summary) {
                    row("thermometer.high", "Sıcaklık", text)
                }
                if !sensors.fanRPM.isEmpty {
                    row("fan", "Fan", sensors.fanRPM.map { L("%ld dev/dk", $0) }.joined(separator: " · "))
                }
            }
            row("clock", "Açık kalma", SystemInfo.uptimeText(info.uptime))
            if info.needsReboot {
                Text(L("Mac %ld günden uzun süredir açık. Yeniden başlatmak belleği ve geçici dosyaları temizler.", SystemInfo.rebootHintDays))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    static func temperatureText(_ summary: SensorSummary) -> String? {
        var parts: [String] = []
        if let cpu = summary.cpu { parts.append("CPU \(Int(cpu.rounded())) °C") }
        if let gpu = summary.gpu { parts.append("GPU \(Int(gpu.rounded())) °C") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func row(_ symbol: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(.secondary)
            Text(L(title)).font(.subheadline)
            Spacer(minLength: 8)
            Text(value).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}
