import Foundation

/// Pil sağlığı. Değer macOS'un Sistem Bilgisi ile aynı kaynaktan (`system_profiler`) okunur.
struct BatteryHealth: Equatable {
    /// Tasarım kapasitesine göre en yüksek kapasite, yüzde.
    var maximumCapacity: Int
    var condition: String

    /// Apple servis eşiği: yüzde 80'in altı.
    static let attentionBelow = 80

    var needsAttention: Bool { maximumCapacity < Self.attentionBelow }

    static func conditionText(_ raw: String) -> String {
        switch raw {
        case "Good": return L("İyi")
        case "Normal": return L("Normal")
        case "Fair": return L("Orta")
        case "Poor": return L("Zayıf")
        case "Service Recommended": return L("Servis önerilir")
        case "Check Battery": return L("Pili kontrol edin")
        default: return raw
        }
    }

    /// `system_profiler SPPowerDataType -json` çıktısını çözer. Pil yoksa veya biçim bozuksa nil döner.
    static func parse(_ data: Data) -> BatteryHealth? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["SPPowerDataType"] as? [[String: Any]] else { return nil }
        for item in items {
            guard let info = item["sppower_battery_health_info"] as? [String: Any],
                  let text = info["sppower_battery_health_maximum_capacity"] as? String else { continue }
            let digits = text.filter(\.isNumber)
            guard let capacity = Int(digits), (1...100).contains(capacity) else { continue }
            let condition = conditionText(info["sppower_battery_health"] as? String ?? "")
            return BatteryHealth(maximumCapacity: capacity, condition: condition)
        }
        return nil
    }

    /// Yaklaşık 1 sn sürer. 8 sn sonra süreç sonlandırılır.
    static func fetch() -> BatteryHealth? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPPowerDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return parse(data)
    }
}
