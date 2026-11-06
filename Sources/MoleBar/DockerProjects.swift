import SwiftUI

/// Docker'daki tek bir öğe: konteyner, hacim veya imaj.
struct DockerEntry: Equatable {
    enum Kind { case container, volume, image }
    let kind: Kind
    let name: String
    let bytes: UInt64
    /// Compose etiketinden gelen proje adı. Etiket yoksa nil, ad eşleşmesi kullanılır.
    let project: String?
}

/// Bir projeye bağlanan Docker öğeleri.
struct DockerProjectTotal: Identifiable {
    let name: String
    let entries: [DockerEntry]
    var id: String { name }
    var total: UInt64 { entries.reduce(0) { $0 + $1.bytes } }
    func bytes(_ kind: DockerEntry.Kind) -> UInt64 { entries.filter { $0.kind == kind }.reduce(0) { $0 + $1.bytes } }
}

/// Docker'ın yazdığı boyut metni ("599.2MB", "217kB (virtual 297MB)"). Ondalık birim kullanır.
enum DockerSize {
    static func parse(_ text: String) -> UInt64? {
        guard let token = text.split(whereSeparator: \.isWhitespace).first else { return nil }
        let units: [(suffix: String, factor: Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("KB", 1e3), ("B", 1)]
        for unit in units where token.hasSuffix(unit.suffix) {
            guard let value = Double(token.dropLast(unit.suffix.count)), value >= 0 else { return nil }
            return UInt64((value * unit.factor).rounded())
        }
        return nil
    }
}

/// `docker system df -v` verisini projeye göre toplar. Salt okunur. MoleBar Docker verisini silmez.
enum DockerProjects {
    static let otherName = "Diğer"
    private static let composeLabel = "com.docker.compose.project="

    static func parse(_ data: Data) -> [DockerEntry] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        func rows(_ key: String) -> [[String: Any]] { root[key] as? [[String: Any]] ?? [] }
        var result: [DockerEntry] = []
        for row in rows("Images") {
            guard let repository = row["Repository"] as? String,
                  let bytes = (row["UniqueSize"] as? String).flatMap(DockerSize.parse) else { continue }
            let tag = row["Tag"] as? String ?? ""
            let name = tag.isEmpty || tag == "<none>" ? repository : "\(repository):\(tag)"
            result.append(DockerEntry(kind: .image, name: name, bytes: bytes, project: nil))
        }
        for row in rows("Containers") {
            guard let name = row["Names"] as? String, let bytes = (row["Size"] as? String).flatMap(DockerSize.parse) else { continue }
            result.append(DockerEntry(kind: .container, name: name, bytes: bytes, project: project(fromLabels: row["Labels"] as? String ?? "")))
        }
        for row in rows("Volumes") {
            guard let name = row["Name"] as? String, let bytes = (row["Size"] as? String).flatMap(DockerSize.parse) else { continue }
            result.append(DockerEntry(kind: .volume, name: name, bytes: bytes, project: project(fromLabels: row["Labels"] as? String ?? "")))
        }
        return result
    }

    /// Compose proje adı. ddev projeleri `ddev-` önekiyle yazılır, ön ek atılır.
    private static func project(fromLabels labels: String) -> String? {
        guard let pair = labels.split(separator: ",").first(where: { $0.hasPrefix(composeLabel) }) else { return nil }
        var value = String(pair.dropFirst(composeLabel.count))
        if value.hasPrefix("ddev-"), value.count > "ddev-".count { value.removeFirst("ddev-".count) }
        return value.isEmpty ? nil : value
    }

    /// Ad iç eşleşmede en az bu uzunlukta aday ister. Kısa genel adlar (`web`, `app`) başka projenin adının ortasında geçer.
    static let minimumInnerLength = 6

    /// Önce adın başında (`ddev-` öneki atılarak) sınırlı sözcük olarak geçen en uzun aday kazanır.
    /// Yoksa adın içinde geçen en az 6 karakterli en uzun aday seçilir. İmaj etiketleri (`…-mia-erp-built`) bu yolla eşleşir.
    /// Sınır: harf veya rakam olmayan karakter ya da uç. 3 karakterden kısa adaylar yok sayılır.
    static func attribute(_ name: String, candidates: [String]) -> String? {
        var lower = name.lowercased()
        if lower.hasPrefix("ddev-") { lower.removeFirst("ddev-".count) }
        let usable = candidates.filter { $0.count >= 3 }
        let leading = usable.filter { startsBounded(lower, $0.lowercased()) }.max { $0.count < $1.count }
        if let leading { return leading }
        return usable
            .filter { $0.count >= minimumInnerLength && containsBounded(lower, $0.lowercased()) }
            .max { $0.count < $1.count }
    }

    private static func isWordCharacter(_ character: Character?) -> Bool { character.map { $0.isLetter || $0.isNumber } ?? false }

    private static func startsBounded(_ text: String, _ word: String) -> Bool {
        guard text.hasPrefix(word) else { return false }
        let next = text.dropFirst(word.count).first
        return !isWordCharacter(next)
    }

    private static func containsBounded(_ text: String, _ word: String) -> Bool {
        var range = text.startIndex..<text.endIndex
        while let found = text.range(of: word, range: range) {
            let before = found.lowerBound == text.startIndex ? nil : text[text.index(before: found.lowerBound)]
            let after = found.upperBound == text.endIndex ? nil : text[found.upperBound]
            if !isWordCharacter(before), !isWordCharacter(after) { return true }
            range = found.upperBound..<text.endIndex
        }
        return false
    }

    /// Projeye göre toplar. Büyükten küçüğe sıralar. Eşleşmeyenler "Diğer" altında en sonda gelir.
    static func group(_ entries: [DockerEntry], candidates: [String]) -> [DockerProjectTotal] {
        let known = candidates + entries.compactMap(\.project)
        var buckets: [String: [DockerEntry]] = [:]
        for entry in entries {
            let key = entry.project ?? attribute(entry.name, candidates: known) ?? otherName
            buckets[key, default: []].append(entry)
        }
        let groups = buckets.map { DockerProjectTotal(name: $0.key, entries: $0.value.sorted { $0.bytes > $1.bytes }) }
        return groups.filter { $0.name != otherName }.sorted { $0.total > $1.total } + groups.filter { $0.name == otherName }
    }

    /// Proje adı veya öğe adı sorguyla eşleşen grupları tutar. Boş sorgu hepsini tutar.
    static func filter(_ groups: [DockerProjectTotal], query: String) -> [DockerProjectTotal] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return groups }
        return groups.filter { ProjectFilter.matches(([$0.name] + $0.entries.map(\.name)).joined(separator: " "), query: query) }
    }

    /// Docker kapalıysa veya 40 saniyede bitmezse boş döner.
    nonisolated static func fetch() -> [DockerEntry] {
        guard let path = CacheCleaner.dockerExecutable() else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["system", "df", "-v", "--format", "json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 40, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return parse(data)
    }
}

@MainActor
final class DockerProjectsModel: ObservableObject {
    @Published private(set) var entries: [DockerEntry] = []
    @Published private(set) var loading = false
    @Published private(set) var loaded = false

    func reloadIfNeeded() { if !loaded { reload() } }

    func reload() {
        guard !loading else { return }
        loading = true
        Task {
            entries = await Task.detached { DockerProjects.fetch() }.value
            loading = false
            loaded = true
        }
    }
}

/// Projeler sayfasında Docker'ın proje bazlı kapladığı alan. Arama kutusuyla süzülür. Salt okunur.
struct DockerProjectsCard: View {
    @StateObject private var model = DockerProjectsModel()
    let query: String
    let candidates: [String]

    private var groups: [DockerProjectTotal] {
        DockerProjects.filter(DockerProjects.group(model.entries, candidates: candidates), query: query)
    }

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardHeader(symbol: "shippingbox", title: "Docker (proje bazlı)", trailing: groups.isEmpty ? "" : formatBytes(groups.reduce(0) { $0 + $1.total }))
                if model.loading { ProgressView().controlSize(.small) }
                Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .glassButton()
                    .controlSize(.small)
                    .disabled(model.loading)
                    .help("Docker verisini yenile")
                    .accessibilityLabel("Docker verisini yenile")
            }
            if groups.isEmpty {
                Text(message).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(group.name).font(.subheadline.weight(.medium))
                            Spacer(minLength: 8)
                            Text(formatBytes(group.total)).font(.subheadline.monospacedDigit())
                        }
                        Text("konteyner \(formatBytes(group.bytes(.container))) · hacim \(formatBytes(group.bytes(.volume))) · imaj \(formatBytes(group.bytes(.image)))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if searching {
                            ForEach(Array(group.entries.enumerated()), id: \.offset) { _, entry in
                                HStack {
                                    Text("\(label(entry.kind)) · \(entry.name)").font(.caption2).lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 8)
                                    Text(formatBytes(entry.bytes)).font(.caption2.monospacedDigit())
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Divider().opacity(0.4)
                }
            }
            Text("Imaj boyutu yalnızca o imaja özgü katmanları sayar. Paylaşılan katmanlar dahil değil. Proje eşleşmesi Compose etiketi ve ad eşleşmesiyle yapılır. Ad eşleşmesi yaklaşıktır. MoleBar Docker verisini silmez.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .onAppear { model.reloadIfNeeded() }
    }

    private var message: String {
        if model.loading || !model.loaded { return "Docker verisi okunuyor..." }
        if model.entries.isEmpty { return "Docker verisi yok. Docker kapalı olabilir." }
        return "Bu aramayla eşleşen Docker öğesi yok."
    }

    private func label(_ kind: DockerEntry.Kind) -> String {
        switch kind {
        case .container: return "konteyner"
        case .volume: return "hacim"
        case .image: return "imaj"
        }
    }
}
