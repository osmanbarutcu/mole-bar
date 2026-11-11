import Foundation

/// Bir günün klasör boyutları. Anahtar görünen ad (örn. "Önbellek", "Mail"), değer bayt.
struct FolderSample: Codable, Identifiable {
    let day: String
    var sizes: [String: UInt64]
    var id: String { day }
}

/// Günde bir klasör boyutu kaydı. Yalnızca UserDefaults'a yazar. Tarama sonuçlarını kullanır, ek tarama yapmaz.
enum FolderLog {
    private static let key = "folderLog"
    private static let limit = 90

    static func load() -> [FolderSample] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([FolderSample].self, from: data)) ?? []
    }

    /// Aynı gün gelen ölçüm, o günün aynı adlı değerlerini değiştirir. Diğer adlar korunur. En çok 90 gün kalır.
    static func merge(_ existing: [FolderSample], sizes: [String: UInt64], day: String) -> [FolderSample] {
        var all = existing
        if let last = all.last, last.day == day {
            all[all.count - 1].sizes.merge(sizes) { _, new in new }
        } else {
            all.append(FolderSample(day: day, sizes: sizes))
        }
        return all.count > limit ? Array(all.suffix(limit)) : all
    }

    static func record(_ sizes: [String: UInt64], now: Date = Date()) {
        guard !sizes.isEmpty else { return }
        let merged = merge(load(), sizes: sizes, day: DiskLog.dayString(now))
        if let data = try? JSONEncoder().encode(merged) { UserDefaults.standard.set(data, forKey: key) }
    }
}

struct FolderGrowthEntry: Identifiable {
    let name: String
    let bytes: UInt64
    let days: Int
    var id: String { name }
}

enum FolderGrowth {
    /// Bu eşiğin altındaki artışlar gürültüdür, listelenmez.
    static let minimumBytes: UInt64 = 20 << 20

    /// Bildirim için tek satır. Artış yoksa nil döner.
    static func summaryLine(_ entries: [FolderGrowthEntry]) -> String? {
        guard let top = entries.max(by: { $0.bytes < $1.bytes }) else { return nil }
        return L("En çok büyüyen: %@ +%@ (%ld gün).", L(top.name), formatBytes(top.bytes), top.days)
    }

    /// En eski ve en yeni ölçümü karşılaştırır. Yalnızca iki ölçümde de bulunan ve büyüyen adlar döner, büyükten küçüğe.
    static func compute(_ samples: [FolderSample]) -> [FolderGrowthEntry] {
        guard samples.count >= 2, let oldest = samples.first, let latest = samples.last,
              let from = DiskLog.date(day: oldest.day), let to = DiskLog.date(day: latest.day) else { return [] }
        let days = Calendar.current.dateComponents([.day], from: from, to: to).day ?? 0
        return latest.sizes.compactMap { name, size -> FolderGrowthEntry? in
            guard let before = oldest.sizes[name], size > before, size - before >= minimumBytes else { return nil }
            return FolderGrowthEntry(name: name, bytes: size - before, days: days)
        }
        .sorted { $0.bytes > $1.bytes }
    }
}
