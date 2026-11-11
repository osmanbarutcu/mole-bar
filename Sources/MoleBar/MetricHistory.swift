import Foundation

/// 30 saniyelik ölçüm. Süre alanları kısa tutulur, çünkü dosyada 7 günde yaklaşık 20 bin satır olur.
/// Satır biçimi: {"t":1762950000,"c":12.5,"m":70.2,"d":81.0,"pc":"Xcode","pm":"Chrome"}. `t` Unix saniyesidir.
struct MetricSample: Codable, Equatable {
    let time: Date
    let cpu: Double
    let memory: Double
    let disk: Double
    /// O anda en çok CPU ve bellek kullanan süreç grubu.
    let topCPU: String?
    let topMemory: String?

    private enum CodingKeys: String, CodingKey {
        case time = "t", cpu = "c", memory = "m", disk = "d", topCPU = "pc", topMemory = "pm"
    }
}

/// Geçmiş için saf işlevler. Dosyaya erişmez.
enum MetricHistory {
    static let maxAge: TimeInterval = 7 * 86_400

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    static func encode(_ sample: MetricSample) -> String? {
        (try? encoder.encode(sample)).map { String(decoding: $0, as: UTF8.self) }
    }

    /// Satırları okur. Bozuk veya yarım satır atlanır.
    static func decode(_ text: String) -> [MetricSample] {
        text.split(separator: "\n").compactMap { try? decoder.decode(MetricSample.self, from: Data($0.utf8)) }
    }

    static func prune(_ samples: [MetricSample], now: Date, maxAge: TimeInterval) -> [MetricSample] {
        let cutoff = now.addingTimeInterval(-maxAge)
        return samples.filter { $0.time >= cutoff }
    }

    /// Son örnekten geriye `duration` saniyelik dilim.
    static func window(_ samples: [MetricSample], duration: TimeInterval) -> [MetricSample] {
        guard let last = samples.last else { return [] }
        let cutoff = last.time.addingTimeInterval(-duration)
        return samples.filter { $0.time >= cutoff }
    }

    /// Grafik için örnekleri eşit gruplara böler ve her grubun ortalamasını alır.
    /// Süreç adı grubun en yüksek değerli örneğinden gelir.
    static func downsample(_ samples: [MetricSample], maxPoints: Int) -> [MetricSample] {
        guard maxPoints > 0 else { return [] }
        guard samples.count > maxPoints else { return samples }
        let size = Double(samples.count) / Double(maxPoints)
        return (0..<maxPoints).map { index in
            let group = samples[Int(Double(index) * size)..<Int(Double(index + 1) * size)]
            let count = Double(group.count)
            return MetricSample(
                time: group.last?.time ?? Date.distantPast,
                cpu: group.reduce(0) { $0 + $1.cpu } / count,
                memory: group.reduce(0) { $0 + $1.memory } / count,
                disk: group.reduce(0) { $0 + $1.disk } / count,
                topCPU: group.max { $0.cpu < $1.cpu }?.topCPU,
                topMemory: group.max { $0.memory < $1.memory }?.topMemory
            )
        }
    }

    /// En yüksek değerli örnek. Liste boşsa nil.
    static func peak(_ samples: [MetricSample], _ metric: KeyPath<MetricSample, Double>) -> (value: Double, sample: MetricSample)? {
        samples.max { $0[keyPath: metric] < $1[keyPath: metric] }.map { ($0[keyPath: metric], $0) }
    }

    /// Örnek: "En yüksek bellek: %92, Sal 14:30, Chrome". Süreç adı yoksa son parça yazılmaz.
    static func peakText(_ title: String, value: Double, sample: MetricSample, process: String?,
                         timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE HH:mm"
        let parts = [String(format: "%@: %%%.0f", title, value), formatter.string(from: sample.time)] + (process.map { [$0] } ?? [])
        return parts.joined(separator: ", ")
    }
}

/// Geçmiş kartındaki süre seçimi. Ham değer `historyWindow` ayarında saklanır.
enum HistoryWindow: String, CaseIterable {
    case hour, day, week

    var seconds: TimeInterval {
        switch self {
        case .hour: return 3_600
        case .day: return 86_400
        case .week: return MetricHistory.maxAge
        }
    }

    var label: String {
        switch self {
        case .hour: return "1 sa"
        case .day: return "24 sa"
        case .week: return "7 gün"
        }
    }
}

/// Örnekleri JSON Lines dosyasına ekler. Yükleme eski satırları dosyadan da siler.
/// Yazma hatası sessiz geçilmez, `ErrorLog` kaydına girer. Geçmiş kaybı uygulamayı durdurmaz.
struct MetricStore {
    let file: URL

    static let shared = MetricStore(file: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MoleBar/metrics.jsonl"))

    func append(_ sample: MetricSample) {
        guard let line = MetricHistory.encode(sample) else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: file.path) {
                try Data().write(to: file)
            }
            let handle = try FileHandle(forUpdating: file)
            defer { try? handle.close() }
            // Çökme sonrası son satır yarım kalabilir. Yeni satır ona yapışmasın diye önce satır sonu eklenir.
            let end = try handle.seekToEnd()
            var prefix = ""
            if end > 0 {
                try handle.seek(toOffset: end - 1)
                if try handle.read(upToCount: 1) != Data("\n".utf8) { prefix = "\n" }
            }
            try handle.write(contentsOf: Data((prefix + line + "\n").utf8))
        } catch {
            ErrorLog.add(source: "Geçmiş", message: "Yazılamadı: \(error.localizedDescription)")
        }
    }

    func load(now: Date = Date(), maxAge: TimeInterval = MetricHistory.maxAge) -> [MetricSample] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        let all = MetricHistory.decode(text)
        let kept = MetricHistory.prune(all, now: now, maxAge: maxAge)
        if kept.count != all.count {
            let body = kept.compactMap(MetricHistory.encode).map { $0 + "\n" }.joined()
            do { try Data(body.utf8).write(to: file, options: .atomic) } catch {
                ErrorLog.add(source: "Geçmiş", message: "Sıkıştırılamadı: \(error.localizedDescription)")
            }
        }
        return kept
    }
}
