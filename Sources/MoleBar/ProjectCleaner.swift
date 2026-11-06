import AppKit
import SwiftUI

struct ProjectArtifact: Identifiable, Hashable {
    let url: URL
    let kind: String
    let project: String
    let lastActive: Date?
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
        return ProjectArtifact(url: url, kind: kind, project: parent.lastPathComponent, lastActive: dates.max() ?? modified(parent))
    }
}

@MainActor
final class ProjectCleaner: ObservableObject {
    static let ageOptions: [(label: String, days: Int)] = [("Hepsi", 0), ("30 gün+", 30), ("90 gün+", 90), ("180 gün+", 180)]

    @Published private(set) var items: [ProjectArtifact] = []
    @Published private(set) var isScanning = false
    @Published var ageIndex = 2
    @Published var selected = Set<URL>()
    @Published var confirming = false
    @Published var notice: String?
    private var started = false

    var visible: [ProjectArtifact] {
        let days = Self.ageOptions[ageIndex].days
        guard days > 0 else { return items.sorted { $0.bytes > $1.bytes } }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return items.filter { ($0.lastActive ?? .distantFuture) < cutoff }.sorted { $0.bytes > $1.bytes }
    }
    var selectedItems: [ProjectArtifact] { visible.filter { selected.contains($0.url) } }
    var selectedBytes: UInt64 { selectedItems.reduce(0) { $0 + $1.bytes } }
    var visibleBytes: UInt64 { visible.reduce(0) { $0 + $1.bytes } }

    func scanIfNeeded() { if !started { scan() } }

    func scan() {
        started = true
        isScanning = true
        items = []
        selected = []
        confirming = false
        Task {
            let found = await Task.detached { Self.scanRoots() }.value
            items = found
            isScanning = false
            for artifact in found {
                let bytes = await Task.detached { FileSizer.size(of: artifact.url) }.value
                if let index = items.firstIndex(where: { $0.id == artifact.id }) {
                    items[index].bytes = bytes
                    items[index].sized = true
                }
            }
            ReclaimStore.save(.projects, bytes: visibleBytes)
        }
    }

    /// Ev klasörü ve bağlı harici diskler. Başlangıç diskinin /Volumes bağlantısı atlanır.
    private nonisolated static func scanRoots() -> [ProjectArtifact] {
        let fm = FileManager.default
        var roots = [fm.homeDirectoryForCurrentUser]
        let volumes = (try? fm.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: nil)) ?? []
        roots += volumes.filter { $0.resolvingSymlinksInPath().path != "/" }
        return roots.flatMap { ProjectScanner.scan(root: $0, maxDepth: 5) }
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
        notice = "\(formatBytes(moved)) Çöp Kutusu'na taşındı." + (failed > 0 ? " \(failed) öğe taşınamadı." : " Finder'dan geri alınabilir.")
        ReclaimStore.save(.projects, bytes: visibleBytes)
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
            }
            HStack(spacing: 10) {
                Text("Son etkinlik").font(.caption).foregroundStyle(.secondary)
                Picker("Son etkinlik", selection: $cleaner.ageIndex) {
                    ForEach(Array(ProjectCleaner.ageOptions.enumerated()), id: \.offset) { index, option in
                        Text(option.label).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)
            }
            if let notice = cleaner.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            ScrollView {
                GlassGroup(spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) { content }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()
                }
            }
            .shadowSafeScroll()
            footer
        }
        .padding(24)
        .onAppear { cleaner.scanIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if cleaner.visible.isEmpty {
            Text(cleaner.isScanning ? "Taranıyor..." : "Bu süreden eski proje çıktısı yok.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(cleaner.visible) { item in
                row(item)
                Divider().opacity(0.4)
            }
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
        guard let date = item.lastActive else { return "tarih yok" }
        let days = Int(Date().timeIntervalSince(date) / 86_400)
        return days <= 0 ? "bugün" : "\(days) gün önce"
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(cleaner.selected.isEmpty ? "Öğe seçin." : "\(cleaner.selectedItems.count) öğe · \(formatBytes(cleaner.selectedBytes))")
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
