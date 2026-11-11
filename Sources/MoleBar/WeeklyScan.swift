import Foundation

/// Haftalık otomatik tarama kuralları ve bildirim metni. Yalnızca ölçer ve bildirir, hiçbir şeyi taşımaz.
enum WeeklyScan {
    static let interval: TimeInterval = 7 * 86_400
    /// Proje çıktısı bu kadar gündür kullanılmıyorsa bildirime girer. Projeler sayfasının varsayılan süzgeciyle aynıdır.
    static let staleProjectDays = 90

    static func isDue(enabled: Bool, lowPower: Bool, last: Date?, now: Date) -> Bool {
        guard enabled, !lowPower else { return false }
        return now.timeIntervalSince(last ?? .distantPast) > interval
    }

    static func body(cleanable: String, cacheBytes: UInt64, staleProjectBytes: UInt64, growth: String?) -> String {
        let parts = [
            cleanable.isEmpty ? nil : "Temizlenebilir alan: \(cleanable).",
            "Önbellek: \(formatBytes(cacheBytes)).",
            staleProjectBytes > 0 ? "\(staleProjectDays) günden eski proje çıktıları: \(formatBytes(staleProjectBytes))." : nil,
            growth,
            "Araçlar sekmesinden inceleyin. Hiçbir şey silinmedi."
        ]
        return parts.compactMap { $0 }.joined(separator: " ")
    }

    /// `limitGB` 0 ise eşik kapalıdır.
    static func exceedsCacheLimit(cacheBytes: UInt64, limitGB: Int) -> Bool {
        limitGB > 0 && cacheBytes >= UInt64(limitGB) * 1_000_000_000
    }
}
