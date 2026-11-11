import Foundation

/// Bir süreç grubu uzun süre yüksek CPU kullanırsa bildirimi bir kez verir.
/// Süreç eşiğin altına inince veya listeden çıkınca sayaç sıfırlanır ve kural yeniden kurulur.
/// CPU değeri tek çekirdek yüzdesidir (çok çekirdekte 100'ü aşabilir).
struct CPUHogAlert {
    static let defaultThreshold = 90.0
    static let defaultDuration: TimeInterval = 300

    let threshold: Double
    let duration: TimeInterval
    private var since: [String: Date] = [:]
    private var notified: Set<String> = []

    init(threshold: Double = defaultThreshold, duration: TimeInterval = defaultDuration) {
        self.threshold = threshold
        self.duration = duration
    }

    /// Yeni ölçümü işler. Bildirilmesi gereken süreç adlarını sıralı döndürür.
    mutating func evaluate(_ groups: [(name: String, cpu: Double)], now: Date) -> [String] {
        let hot = Set(groups.filter { $0.cpu >= threshold }.map(\.name))
        since = hot.reduce(into: [:]) { result, name in result[name] = since[name] ?? now }
        notified = notified.intersection(hot)
        let due = hot.filter { name in
            !notified.contains(name) && now.timeIntervalSince(since[name] ?? now) >= duration
        }
        notified.formUnion(due)
        return due.sorted()
    }

    static func body(for names: [String]) -> String {
        "\(names.joined(separator: ", ")) \(Int(defaultDuration / 60)) dakikadır %\(Int(defaultThreshold)) üstü CPU kullanıyor. "
            + "Süreçler sayfasından inceleyin."
    }
}
