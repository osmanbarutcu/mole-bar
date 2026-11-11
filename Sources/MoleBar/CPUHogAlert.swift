import Foundation

/// Bir uygulama (aynı adlı süreç grubu) uzun süre yüksek CPU kullanırsa bildirimi bir kez verir.
/// Grup eşiğin altına inince veya listeden çıkınca sayaç sıfırlanır ve kural yeniden kurulur.
/// CPU değeri grubun toplamıdır ve tek çekirdek yüzdesiyle ölçülür (100'ü aşabilir).
struct CPUHogAlert {
    static let defaultThreshold = 90.0
    static let defaultDuration: TimeInterval = 300
    /// Ölçüm 4 saniyede bir gelir. Bundan uzun boşluk uyku veya kapalı ayar demektir.
    /// Boşluktan sonra sayaçlar sıfırlanır, yoksa uyanınca hemen yanlış bildirim gelir.
    static let defaultMaxGap: TimeInterval = 30

    let threshold: Double
    let duration: TimeInterval
    let maxGap: TimeInterval
    private var since: [String: Date] = [:]
    private var notified: Set<String> = []
    private var lastEvaluated: Date?

    init(threshold: Double = defaultThreshold, duration: TimeInterval = defaultDuration, maxGap: TimeInterval = defaultMaxGap) {
        self.threshold = threshold
        self.duration = duration
        self.maxGap = maxGap
    }

    /// Yeni ölçümü işler. Bildirilmesi gereken grup adlarını sıralı döndürür.
    mutating func evaluate(_ groups: [(name: String, cpu: Double)], now: Date) -> [String] {
        if let last = lastEvaluated, now.timeIntervalSince(last) > maxGap { since = [:] }
        lastEvaluated = now
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
        L(
            "%@ %ld dakikadır toplam %%%ld üstü CPU kullanıyor. Süreçler sayfasından inceleyin.",
            names.joined(separator: ", "), Int(defaultDuration / 60), Int(defaultThreshold)
        )
    }
}
