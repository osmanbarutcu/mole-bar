import AppKit
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
        /// Her satırın bir eylemi var. Kendi öğelerinde sayfa açılır. Konteynerlerde uygulama açılır veya komut kopyalanır.
        /// Hiçbiri veriyi silmez. Silmeyi ilgili uygulama veya kullanıcı yapar.
        var action: Action? { section.map(Action.openPage) ?? DiskExplainer.outsideActions[name] }
    }

    enum Action: Equatable {
        case openPage(MainSection)
        case openApp(bundleID: String, name: String, label: String)
        case copyCommand(String)
    }

    /// MoleBar'ın silmediği öğeler için eylemler. OrbStack kimliği kurulu uygulamanın Info.plist dosyasından okundu.
    static let outsideActions: [String: Action] = [
        "Mail": .openApp(bundleID: "com.apple.mail", name: "Mail", label: "Mail'i aç"),
        "OrbStack": .openApp(bundleID: "dev.kdrag0n.MacVirt", name: "OrbStack", label: "OrbStack'i aç"),
        "Docker Desktop": .openApp(bundleID: "com.docker.docker", name: "Docker Desktop", label: "Docker'ı aç"),
        "Spotlight dizini": .copyCommand("sudo mdutil -E /")
    ]

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
        "Mail": "Mail'de iletileri seçin, İleti menüsünden İlişikleri Sil'i seçin. Ek, iletiden kalıcı çıkar."
    ]

    /// Yolun gerçek diskinin adı. Sembolik bağ önce çözülür. OrbStack verisi `~/Library` altındaki bağdan `brtc-disk`'e gider.
    static func volumeName(of url: URL) -> String? {
        (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.volumeNameKey]))?.volumeName
    }

    /// Disk bilgisi olmayan kapsayıcılar ana diskte sayılır.
    @_disfavoredOverload
    static func entries(containers: [(name: String, bytes: UInt64?)], cacheBytes: Int, trashBytes: Int,
                        projectsByDisk: [String: UInt64], bootDisk: String) -> [Entry] {
        entries(containers: containers.map { (name: $0.name, bytes: $0.bytes, disk: nil) }, cacheBytes: cacheBytes,
                trashBytes: trashBytes, projectsByDisk: projectsByDisk, bootDisk: bootDisk)
    }

    /// Önbellek ve Çöp Kutusu ev klasöründedir, yani ana diskte. Kapsayıcı ve proje çıktısı kendi diskine yazılır.
    /// `cacheBytes` negatifse taranmadı demektir (ReclaimStore varsayılanı -1).
    static func entries(containers: [(name: String, bytes: UInt64?, disk: String?)], cacheBytes: Int, trashBytes: Int,
                        projectsByDisk: [String: UInt64], bootDisk: String) -> [Entry] {
        var result: [Entry] = containers.compactMap { item in
            guard let bytes = item.bytes else { return nil }
            return Entry(name: item.name, bytes: bytes, advice: adviceByContainer[item.name] ?? "MoleBar dokunmaz.", section: nil,
                         disk: item.disk ?? bootDisk)
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
            containers: cleaner.containers.map { (name: $0.name, bytes: $0.bytes, disk: $0.disk) },
            cacheBytes: cache, trashBytes: trash, projectsByDisk: projects, bootDisk: boot)
        let missing = DiskExplainer.unscanned(cacheBytes: cache, projectsScanned: !projectsJSON.isEmpty)
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(symbol: "questionmark.circle", title: "Disk neden dolu?")
            ForEach(DiskExplainer.grouped(entries, bootDisk: boot)) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(group.disk == boot ? L("%@ (ana disk)", group.disk) : group.disk).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
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
                 ? L("Büyük dosyalar listesi ayrıdır. OrbStack ve Spotlight dosyalarını da içerdiği için buraya eklenmedi.")
                 : L("Taranmadı: %@. Listede eksik olabilir.", missing.map { L($0) }.joined(separator: ", ")))
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let notice = cleaner.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        // Kapsayıcı ve önbellek ölçümü Önbellek sayfasında başlardı. Doğrudan Diskler'e gelinse de liste dolsun.
        .onAppear { cleaner.scanIfNeeded() }
    }

    private func row(_ entry: DiskExplainer.Entry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L(entry.name)).font(.subheadline)
                Text(L(entry.advice)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(formatBytes(entry.bytes)).font(.subheadline.weight(.medium).monospacedDigit())
            if let action = entry.action {
                Button(label(action)) { run(action) }.glassButton().controlSize(.small)
            }
        }
    }

    private func label(_ action: DiskExplainer.Action) -> String {
        switch action {
        case .openPage: return L("Aç")
        case .openApp(_, _, let label): return L(label)
        case .copyCommand: return L("Komutu kopyala")
        }
    }

    private func run(_ action: DiskExplainer.Action) {
        switch action {
        case .openPage(let section):
            open(section)
        case .openApp(let bundleID, let name, _):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                cleaner.notice = L("%@ uygulaması bulunamadı.", name)
                return
            }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            cleaner.notice = L("%1$@ açıldı. MoleBar silmez. Satırdaki adımı %1$@ içinde uygulayın.", name)
        case .copyCommand(let command):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            cleaner.notice = L("Komut panoya kopyalandı: %@. Terminal'de siz çalıştırın.", command)
        }
    }
}
