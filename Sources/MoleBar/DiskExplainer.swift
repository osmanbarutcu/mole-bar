import SwiftUI

/// Proje çıktısı toplamlarının disk bazında kaydı. UserDefaults'a JSON olarak yazılır.
enum ProjectDiskTotals {
    static let key = "reclaim.projectsByDisk"

    static func encode(_ totals: [String: UInt64]) -> String {
        guard let data = try? JSONEncoder().encode(totals) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func decode(_ text: String) -> [String: UInt64] {
        (try? JSONDecoder().decode([String: UInt64].self, from: Data(text.utf8))) ?? [:]
    }
}

/// "Disk neden dolu?" listesi. Mevcut ölçümleri disk bazında toplar. Ek tarama yapmaz.
enum DiskExplainer {
    struct Entry: Identifiable {
        let name: String
        let bytes: UInt64
        let advice: String
        /// MoleBar'ın kendi temizleyebildiği öğede sayfa. Diğerlerinde nil, MoleBar dokunmaz.
        let section: MainSection?
        let disk: String
        var id: String { disk + "/" + name }
    }

    struct Group: Identifiable {
        let disk: String
        let entries: [Entry]
        var id: String { disk }
        var total: UInt64 { entries.reduce(0) { $0 + $1.bytes } }
    }

    private static let minimumBytes: UInt64 = 100 << 20
    private static let adviceByContainer: [String: String] = [
        "OrbStack": "Docker temizliği imajı küçültmez. OrbStack'te disk küçültmeyi deneyin.",
        "Docker Desktop": "Docker Desktop ayarlarında disk imajını küçültün.",
        "Spotlight dizini": "Boyut anormalse Terminal'de `sudo mdutil -E /` dizini yeniden kurar.",
        "Mail": "Mail'de Posta Kutusu > Ek Dosyaları Kaldır."
    ]

    /// Kapsayıcı, önbellek ve Çöp Kutusu ev klasöründedir, yani ana diskte. Proje çıktısı her diskte ayrı girdidir.
    /// `cacheBytes` negatifse taranmadı demektir (ReclaimStore varsayılanı -1).
    static func entries(containers: [(name: String, bytes: UInt64?)], cacheBytes: Int, trashBytes: Int,
                        projectsByDisk: [String: UInt64], bootDisk: String) -> [Entry] {
        var result: [Entry] = containers.compactMap { item in
            guard let bytes = item.bytes else { return nil }
            return Entry(name: item.name, bytes: bytes, advice: adviceByContainer[item.name] ?? "MoleBar dokunmaz.", section: nil, disk: bootDisk)
        }
        func add(_ name: String, _ value: Int, _ advice: String, _ section: MainSection) {
            if value > 0 { result.append(Entry(name: name, bytes: UInt64(value), advice: advice, section: section, disk: bootDisk)) }
        }
        add("Uygulama önbelleği", cacheBytes, "Önbellek sayfasından Çöp Kutusu'na taşıyın.", .caches)
        add("Çöp Kutusu", trashBytes, "Boşaltınca alan açılır.", .caches)
        for (disk, bytes) in projectsByDisk {
            result.append(Entry(name: "Proje çıktıları", bytes: bytes,
                                advice: "Eski projelerin node_modules ve vendor klasörlerini taşıyın.", section: .projects, disk: disk))
        }
        return result.filter { $0.bytes >= minimumBytes }.sorted { $0.bytes > $1.bytes }
    }

    /// Ana disk her zaman ilk gruptur, girdisi olmasa da. Diğer diskler toplamına göre sıralanır.
    static func grouped(_ entries: [Entry], bootDisk: String) -> [Group] {
        let byDisk = Dictionary(grouping: entries, by: \.disk)
        let others = byDisk.filter { $0.key != bootDisk }
            .map { Group(disk: $0.key, entries: $0.value) }
            .sorted { $0.total > $1.total }
        return [Group(disk: bootDisk, entries: byDisk[bootDisk] ?? [])] + others
    }

    static func unscanned(cacheBytes: Int, projectsScanned: Bool) -> [String] {
        var names: [String] = []
        if cacheBytes < 0 { names.append("Önbellek") }
        if !projectsScanned { names.append("Proje çıktıları") }
        return names
    }
}

struct DiskExplainerCard: View {
    @ObservedObject var cleaner: CacheCleaner
    let open: (MainSection) -> Void
    @AppStorage("reclaim.cache") private var cache = -1
    @AppStorage("reclaim.trash") private var trash = -1
    @AppStorage(ProjectDiskTotals.key) private var projectsJSON = ""

    var body: some View {
        let boot = ProjectFilter.bootDiskName()
        let projects = ProjectDiskTotals.decode(projectsJSON)
        let entries = DiskExplainer.entries(
            containers: cleaner.containers.map { ($0.name, $0.bytes) },
            cacheBytes: cache, trashBytes: trash, projectsByDisk: projects, bootDisk: boot)
        let missing = DiskExplainer.unscanned(cacheBytes: cache, projectsScanned: !projectsJSON.isEmpty)
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(symbol: "questionmark.circle", title: "Disk neden dolu?")
            ForEach(DiskExplainer.grouped(entries, bootDisk: boot)) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(group.disk + (group.disk == boot ? " (ana disk)" : "")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        if !group.entries.isEmpty { Text(formatBytes(group.total)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    }
                    if group.entries.isEmpty {
                        Text("100 MB üstü girdi yok.").font(.caption2).foregroundStyle(.secondary)
                    }
                    ForEach(group.entries.prefix(5)) { entry in row(entry) }
                }
            }
            Text(missing.isEmpty
                 ? "Büyük dosyalar listesi ayrıdır. OrbStack ve Spotlight dosyalarını da içerdiği için buraya eklenmedi."
                 : "Taranmadı: \(missing.joined(separator: ", ")). Listede eksik olabilir.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func row(_ entry: DiskExplainer.Entry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.subheadline)
                Text(entry.advice).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(formatBytes(entry.bytes)).font(.subheadline.weight(.medium).monospacedDigit())
            if let section = entry.section {
                Button("Aç") { open(section) }.glassButton().controlSize(.small)
            }
        }
    }
}
