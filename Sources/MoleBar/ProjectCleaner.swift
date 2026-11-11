import AppKit
import SwiftUI

struct ProjectArtifact: Identifiable, Hashable {
    let url: URL
    let kind: String
    let project: String
    let lastActive: Date?
    /// Öğenin bulunduğu birimin adı (örn. "Macintosh HD", "brtc-disk").
    let disk: String
    var bytes: UInt64 = 0
    var sized = false
    var id: URL { url }
}

/// Proje klasörlerindeki yeniden üretilebilir derleme çıktılarını bulur. Salt okunur.
enum ProjectScanner {
    /// Klasör adı, projeyi kanıtlayan dosya. Dosya yoksa klasör listelenmez.
    private static let rules: [(dir: String, marker: String)] = [
        ("node_modules", "package.json"), (".build", "Package.swift"), ("vendor", "composer.json"),
        ("target", "Cargo.toml"), ("Pods", "Podfile"), (".venv", ".venv/pyvenv.cfg"), ("venv", "venv/pyvenv.cfg")
    ]
    private static let skipped: Set<String> = ["Library", "OrbStack", ".git", ".Trash", "Applications"]

    static func scan(root: URL, maxDepth: Int) -> [ProjectArtifact] {
        var result: [ProjectArtifact] = []
        walk(root, depth: 0, maxDepth: maxDepth, into: &result)
        return result.sorted { $0.url.path < $1.url.path }
    }

    private static func walk(_ dir: URL, depth: Int, maxDepth: Int, into result: inout [ProjectArtifact]) {
        if Task.isCancelled { return }
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isVolumeKey, .isPackageKey]
        guard let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: []) else { return }
        for child in children {
            let name = child.lastPathComponent
            let values = try? child.resourceValues(forKeys: Set(keys))
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            if let rule = rules.first(where: { $0.dir == name }), isArtifact(child, rule: rule) {
                result.append(artifact(child, kind: name))
                continue // Çıktının içine inilmez. İç içe node_modules ayrıca sayılmaz.
            }
            if depth + 1 >= maxDepth || skipped.contains(name) || name.hasPrefix(".") || values?.isVolume == true || values?.isPackage == true { continue }
            walk(child, depth: depth + 1, maxDepth: maxDepth, into: &result)
        }
    }

    private static func isArtifact(_ url: URL, rule: (dir: String, marker: String)) -> Bool {
        let parent = url.deletingLastPathComponent()
        // Marker `.venv/pyvenv.cfg` gibi klasör içinde ya da `package.json` gibi kardeş dosya olabilir.
        let candidate = rule.marker.contains("/") ? parent.appendingPathComponent(rule.marker) : parent.appendingPathComponent(rule.marker)
        return FileManager.default.fileExists(atPath: candidate.path)
    }

    private static func artifact(_ url: URL, kind: String) -> ProjectArtifact {
        let parent = url.deletingLastPathComponent()
        let candidates = [
            "package.json", "Package.swift", "composer.json", "Cargo.toml", "Podfile", "pyproject.toml", "requirements.txt",
            ".git/index", ".git/HEAD", ".git/logs/HEAD"
        ]
        func modified(_ url: URL) -> Date? {
            (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        }
        let dates = candidates.compactMap { modified(parent.appendingPathComponent($0)) }
        // Hiçbiri yoksa proje klasörünün kendi tarihi kullanılır. Tarihsiz proje eski sayılmaz.
        let disk = (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? L("Bilinmeyen disk")
        return ProjectArtifact(url: url, kind: kind, project: parent.lastPathComponent, lastActive: dates.max() ?? modified(parent), disk: disk)
    }
}

/// Disk ve gün eşiği süzgeci. Saf işlev, testlenir.
enum ProjectFilter {
    /// `disk` nil ise tüm diskler. `minDays` 0 ise yaş süzgeci yok. Tarihsiz öğe yaş süzgecinde listelenmez.
    static func apply(_ items: [ProjectArtifact], disk: String?, minDays: Int, now: Date = Date()) -> [ProjectArtifact] {
        let cutoff = now.addingTimeInterval(-Double(minDays) * 86_400)
        return items
            .filter { disk == nil || $0.disk == disk }
            .filter { minDays == 0 || ($0.lastActive ?? .distantFuture) < cutoff }
            .sorted { $0.bytes > $1.bytes }
    }

    /// Boşlukla ayrılmış her sözcük metinde geçmeli. Büyük/küçük harf ve aksan duyarsızdır. Boş sorgu her şeyle eşleşir.
    static func matches(_ haystack: String, query: String) -> Bool {
        let text = fold(haystack)
        return query.split(whereSeparator: \.isWhitespace).allSatisfy { text.contains(fold(String($0))) }
    }

    /// Harf büyüklüğünü ve aksanı kaldırır. Noktasız ı aksan sayılmaz, elle i yapılır.
    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).replacingOccurrences(of: "ı", with: "i")
    }

    /// Proje adı, yol ve tür üzerinde arar.
    static func search(_ items: [ProjectArtifact], query: String) -> [ProjectArtifact] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return items }
        return items.filter { matches("\($0.project) \($0.kind) \($0.url.path)", query: query) }
    }

    /// Öğesi olmayan diskler de listelenir. Böylece taranan her disk seçicide görünür.
    static func diskNames(_ items: [ProjectArtifact], scanned: [String] = []) -> [String] {
        Set(items.map(\.disk)).union(scanned).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Yaş süzgecine uyan öğelerin disk bazında toplamı. Öğesi olmayan disk sözlükte yoktur.
    static func totals(_ items: [ProjectArtifact], minDays: Int, now: Date = Date()) -> [String: UInt64] {
        var result: [String: UInt64] = [:]
        for item in apply(items, disk: nil, minDays: minDays, now: now) { result[item.disk, default: 0] += item.bytes }
        return result
    }

    /// Başlangıç diskinin adı. "Disk neden dolu?" kartı yalnızca bu diski anlatır.
    static func bootDiskName() -> String {
        (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? "Macintosh HD"
    }
}

@MainActor
final class ProjectCleaner: ObservableObject {
    static let ageOptions: [(label: String, days: Int)] = [("Hepsi", 0), ("30 gün+", 30), ("90 gün+", 90), ("180 gün+", 180)]

    @Published private(set) var items: [ProjectArtifact] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scannedDisks: [String] = []
    @Published var ageIndex = 2
    /// nil ise tüm diskler.
    @Published var diskFilter: String?
    @Published var selected = Set<URL>()
    @Published var confirming = false
    @Published var notice: String?
    @Published var query = ""
    @Published private(set) var projectSizes: [URL: UInt64] = [:]
    private var sizing = Set<URL>()
    private var started = false

    /// Arama doluyken yaş süzgeci uygulanmaz. Aktif bir projeyi aramak mümkün olmalı.
    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var visible: [ProjectArtifact] {
        let minDays = isSearching ? 0 : Self.ageOptions[ageIndex].days
        return ProjectFilter.search(ProjectFilter.apply(items, disk: diskFilter, minDays: minDays), query: query)
    }

    struct MatchedProject: Identifiable {
        let dir: URL
        let artifactBytes: UInt64
        var id: URL { dir }
        var name: String { dir.lastPathComponent }
    }

    /// Aramayla eşleşen proje klasörleri ve her birindeki çıktı toplamı. Arama boşsa liste boştur.
    var matchedProjects: [MatchedProject] {
        guard isSearching else { return [] }
        var bytes: [URL: UInt64] = [:]
        for item in visible { bytes[item.url.deletingLastPathComponent(), default: 0] += item.bytes }
        return bytes.map { MatchedProject(dir: $0.key, artifactBytes: $0.value) }.sorted { $0.artifactBytes > $1.artifactBytes }
    }

    /// Docker eşleştirmesinde aday olarak kullanılan proje adları.
    var projectNames: [String] { Array(Set(items.map(\.project))) }

    /// En çok bu kadar proje klasörünün toplam boyutu ölçülür. Büyük klasörde tarama uzun sürer.
    static let maxSizedProjects = 6

    /// Eşleşen proje klasörlerinin toplam boyutunu arka planda ölçer. Aynı klasör bir kez ölçülür.
    func sizeMatchedProjects() {
        for project in matchedProjects.prefix(Self.maxSizedProjects) where projectSizes[project.dir] == nil && !sizing.contains(project.dir) {
            let dir = project.dir
            sizing.insert(dir)
            Task {
                let bytes = await Task.detached { FileSizer.size(of: dir) }.value
                projectSizes[dir] = bytes
                sizing.remove(dir)
            }
        }
    }
    var diskNames: [String] { ProjectFilter.diskNames(items, scanned: scannedDisks) }
    /// Yaş süzgecine uyan öğelerin disk bazında toplamı. Disk seçici etiketinde görünür.
    func bytes(onDisk disk: String?) -> UInt64 {
        ProjectFilter.apply(items, disk: disk, minDays: Self.ageOptions[ageIndex].days).reduce(0) { $0 + $1.bytes }
    }
    var selectedItems: [ProjectArtifact] { visible.filter { selected.contains($0.url) } }
    var selectedBytes: UInt64 { selectedItems.reduce(0) { $0 + $1.bytes } }
    var visibleBytes: UInt64 { visible.reduce(0) { $0 + $1.bytes } }

    func scanIfNeeded() { if !started { scan() } }

    func scan() {
        started = true
        isScanning = true
        items = []
        projectSizes = [:]
        selected = []
        confirming = false
        Task {
            let (found, disks) = await Task.detached { Self.scanRoots() }.value
            scannedDisks = disks
            items = found
            isScanning = false
            if let chosen = diskFilter, !diskNames.contains(chosen) { diskFilter = nil }
            for artifact in found {
                let bytes = await Task.detached { FileSizer.size(of: artifact.url) }.value
                if let index = items.firstIndex(where: { $0.id == artifact.id }) {
                    items[index].bytes = bytes
                    items[index].sized = true
                }
            }
            saveReclaim()
        }
    }

    /// Toplam ve disk bazlı toplamlar kaydedilir. "Disk neden dolu?" kartı her diski ayrı gösterir.
    private func saveReclaim() {
        ReclaimStore.save(.projects, bytes: bytes(onDisk: nil))
        let totals = ProjectFilter.totals(items, minDays: Self.ageOptions[ageIndex].days)
        UserDefaults.standard.set(ProjectDiskTotals.encode(totals), forKey: ProjectDiskTotals.key)
    }

    /// Haftalık tarama için `minDays` günden eski proje çıktılarının toplamı. Listeyi ve seçimi değiştirmez.
    /// Gözetimsiz çalışır: ağ diskleri taranmaz ve yalnızca yaş süzgecini geçen öğeler ölçülür.
    nonisolated static func staleBytes(minDays: Int) -> UInt64 {
        ProjectFilter.apply(scanRoots(localOnly: true).0, disk: nil, minDays: minDays)
            .reduce(0) { $0 + FileSizer.size(of: $1.url) }
    }

    /// Ev klasörü ve bağlı harici diskler. Başlangıç diskinin /Volumes bağlantısı atlanır.
    /// `localOnly` açıkken ağ diskleri (SMB, NFS) atlanır. Ölü bağlantıda tarama takılmasın.
    private nonisolated static func scanRoots(localOnly: Bool = false) -> ([ProjectArtifact], [String]) {
        let fm = FileManager.default
        var roots = [fm.homeDirectoryForCurrentUser]
        let volumes = (try? fm.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: nil)) ?? []
        roots += volumes.filter { volume in
            guard volume.resolvingSymlinksInPath().path != "/" else { return false }
            guard localOnly else { return true }
            return (try? volume.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal == true
        }
        let names = roots.compactMap { (try? $0.resourceValues(forKeys: [.volumeNameKey]))?.volumeName }
        return (roots.flatMap { ProjectScanner.scan(root: $0, maxDepth: 5) }, Array(Set(names)))
    }

    func toggle(_ item: ProjectArtifact) {
        if selected.contains(item.url) { selected.remove(item.url) } else { selected.insert(item.url) }
        confirming = false
    }

    func moveSelected() {
        let targets = selectedItems
        confirming = false
        var failed = 0
        var moved: UInt64 = 0
        for item in targets {
            guard TrashGuard.canTrash(item.url) else { failed += 1; continue }
            do {
                try TrashGuard.trash(item.url, bytes: item.bytes, source: "Projeler")
                moved += item.bytes
                items.removeAll { $0.id == item.id }
                selected.remove(item.url)
            } catch { failed += 1 }
        }
        notice = L("%@ Çöp Kutusu'na taşındı.", formatBytes(moved)) + (failed > 0 ? L(" %ld öğe taşınamadı.", failed) : L(" Finder'dan geri alınabilir."))
        saveReclaim()
    }
}

struct ProjectsPage: View {
    @ObservedObject var cleaner: ProjectCleaner

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Projeler").font(.title2.weight(.semibold))
                Spacer()
                if cleaner.isScanning { ProgressView().controlSize(.small) }
                else if !cleaner.visible.isEmpty { Text(formatBytes(cleaner.visibleBytes)).font(.headline.monospacedDigit()) }
                Button { cleaner.scan() } label: { Image(systemName: "arrow.clockwise") }
                    .glassButton()
                    .disabled(cleaner.isScanning)
                    .help("Yeniden tara")
                    .accessibilityLabel("Yeniden tara")
            }
            HStack(spacing: 10) {
                Text("Son etkinlik").font(.caption).foregroundStyle(.secondary)
                Picker("Son etkinlik", selection: $cleaner.ageIndex) {
                    ForEach(Array(ProjectCleaner.ageOptions.enumerated()), id: \.offset) { index, option in
                        Text(L(option.label)).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)
                .disabled(cleaner.isSearching)
                if cleaner.isSearching { Text("Arama yaş süzgecini yok sayar.").font(.caption2).foregroundStyle(.secondary) }
            }
            searchField
            if cleaner.diskNames.count > 1 { diskPicker }
            if let notice = cleaner.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            ScrollView {
                GlassGroup(spacing: 12) {
                    VStack(alignment: .leading, spacing: 14) {
                        if cleaner.isSearching && !cleaner.matchedProjects.isEmpty { matchedCard }
                        DockerProjectsCard(query: cleaner.query, candidates: cleaner.projectNames)
                        VStack(alignment: .leading, spacing: 0) { content }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard()
                    }
                }
            }
            .shadowSafeScroll()
            footer
        }
        .padding(24)
        .onAppear { cleaner.scanIfNeeded() }
        .onChange(of: cleaner.query) { cleaner.sizeMatchedProjects() }
        .onChange(of: cleaner.items.count) { cleaner.sizeMatchedProjects() }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Proje ara (örn. mia-erp)", text: $cleaner.query)
                .textFieldStyle(.plain)
            if cleaner.isSearching {
                Button { cleaner.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Aramayı temizle")
                    .accessibilityLabel("Aramayı temizle")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 420)
        .glassCard()
    }

    /// Aramayla eşleşen projelerin klasör toplamı ve içindeki çıktılar. Klasör toplamı arka planda ölçülür.
    private var matchedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(symbol: "folder", title: "Eşleşen projeler", trailing: L("%ld proje", cleaner.matchedProjects.count))
            ForEach(Array(cleaner.matchedProjects.enumerated()), id: \.element.id) { index, project in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(project.name).font(.subheadline.weight(.medium))
                        Text(project.dir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 0) {
                        if let total = cleaner.projectSizes[project.dir] {
                            Text(formatBytes(total)).font(.subheadline.monospacedDigit())
                            Text("klasör toplamı").font(.caption2).foregroundStyle(.secondary)
                        } else if index < ProjectCleaner.maxSizedProjects {
                            ProgressView().controlSize(.mini)
                        } else {
                            Text("ölçülmedi").font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(L("çıktılar %@", formatBytes(project.artifactBytes))).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            Text(L("Klasör toplamı projenin tüm dosyalarını sayar. Yalnızca çıktısı (node_modules, vendor vb.) olan projeler bulunur. En çok %ld proje ölçülür.", ProjectCleaner.maxSizedProjects))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// Birden fazla disk varsa hangisini listeleyeceğinizi seçersiniz. Etiketlerde yaş süzgecine uyan toplam görünür.
    private var diskPicker: some View {
        HStack(spacing: 10) {
            Text("Disk").font(.caption).foregroundStyle(.secondary)
            Picker("Disk", selection: $cleaner.diskFilter) {
                Text(L("Hepsi %@", formatBytes(cleaner.bytes(onDisk: nil)))).tag(String?.none)
                ForEach(cleaner.diskNames, id: \.self) { name in
                    Text("\(name) \(formatBytes(cleaner.bytes(onDisk: name)))").tag(String?.some(name))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 560)
        }
    }

    @ViewBuilder
    private var content: some View {
        if cleaner.visible.isEmpty {
            Text(L(cleaner.isScanning ? "Taranıyor..." : (cleaner.isSearching ? "Aramayla eşleşen proje çıktısı yok." : "Bu süreden eski proje çıktısı yok.")))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(groups, id: \.disk) { group in
                if showHeaders {
                    HStack {
                        Text(group.disk).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text(formatBytes(group.items.reduce(0) { $0 + $1.bytes })).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                }
                ForEach(group.items) { item in
                    row(item)
                    Divider().opacity(0.4)
                }
            }
        }
    }

    /// "Hepsi" seçiliyken disk başlıklarıyla ayrı gruplar. Tek disk seçiliyse başlık gerekmez.
    private var showHeaders: Bool { cleaner.diskFilter == nil && cleaner.diskNames.count > 1 }

    private var groups: [(disk: String, items: [ProjectArtifact])] {
        let visible = cleaner.visible
        return cleaner.diskNames.compactMap { name in
            let rows = visible.filter { $0.disk == name }
            return rows.isEmpty ? nil : (name, rows)
        }
    }

    private func row(_ item: ProjectArtifact) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { cleaner.selected.contains(item.url) }, set: { _ in cleaner.toggle(item) }))
                .labelsHidden()
                .toggleStyle(.checkbox)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(item.project) · \(item.kind)").font(.subheadline).lineLimit(1).truncationMode(.middle)
                Text(item.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~") + " · " + activity(item))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 8)
            if item.sized { Text(formatBytes(item.bytes)).font(.subheadline.weight(.medium).monospacedDigit()) }
            else { ProgressView().controlSize(.mini) }
        }
        .padding(.vertical, 7)
    }

    private func activity(_ item: ProjectArtifact) -> String {
        guard let date = item.lastActive else { return L("tarih yok") }
        let days = Int(Date().timeIntervalSince(date) / 86_400)
        return days <= 0 ? L("bugün") : L("%ld gün önce", days)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(cleaner.selected.isEmpty ? L("Öğe seçin.") : L("%ld öğe · %@", cleaner.selectedItems.count, formatBytes(cleaner.selectedBytes)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if cleaner.confirming {
                    Text("Çöp Kutusu'na taşınır. Sonra yeniden kurulum gerekir.").font(.caption)
                    Button("Taşı") { cleaner.moveSelected() }.glassProminentButton()
                    Button("Vazgeç") { cleaner.confirming = false }.glassButton()
                } else {
                    Button { cleaner.confirming = true } label: { Label("Çöp Kutusu'na taşı", systemImage: "trash") }
                        .glassButton()
                        .disabled(cleaner.selected.isEmpty)
                }
            }
            Text("Tarama ev klasörünü ve bağlı diskleri okur. Yalnızca yeniden üretilebilir çıktılar listelenir: node_modules, .build, vendor, target, Pods, .venv. Silme yok, yalnızca Çöp Kutusu'na taşıma.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
