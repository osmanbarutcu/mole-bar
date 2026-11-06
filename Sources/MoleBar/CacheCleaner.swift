import AppKit
import SwiftUI

enum CacheCategory: String, CaseIterable {
    case app = "Uygulama önbelleği"
    case logs = "Günlükler"
    case dev = "Geliştirici önbelleği"
}

/// Konteyner çalışma zamanı verisi (OrbStack, Docker). Yalnızca gösterilir, MoleBar silmez.
struct ContainerData: Identifiable {
    let name: String
    let url: URL
    /// nil ise boyut okunamadı (izin yok).
    let bytes: UInt64?
    var id: URL { url }
}

/// `docker system df` satırı.
struct DockerRow: Identifiable {
    let type: String
    let size: String
    let reclaimable: String
    var id: String { type }
}

struct CacheItem: Identifiable {
    let url: URL
    let category: CacheCategory
    let bytes: UInt64
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

/// Yeniden üretilebilen kullanıcı önbelleklerini listeler. Tarama salt okunurdur.
/// Seçilenler Çöp Kutusu'na taşınır (geri alınabilir). Çöp Kutusu'nu boşaltmak kalıcıdır ve ayrı onay ister.
/// Apple sistem önbellekleri (com.apple.*) ve MoleBar kendisi listelenmez.
@MainActor
final class CacheCleaner: ObservableObject {
    @Published private(set) var items: [CacheItem] = []
    @Published private(set) var isScanning = false
    @Published private(set) var trashBytes: UInt64 = 0
    @Published private(set) var hasScanned = false
    @Published private(set) var containers: [ContainerData] = []
    @Published private(set) var dockerRows: [DockerRow] = []
    @Published private(set) var snapshots: [LocalSnapshot] = []
    @Published var selection = Set<URL>()
    @Published var confirmingMove = false
    @Published var confirmingEmpty = false
    @Published var notice: String?

    private var task: Task<Void, Never>?
    private var started = false

    var selectedBytes: UInt64 { items.filter { selection.contains($0.url) }.reduce(0) { $0 + $1.bytes } }

    func items(in category: CacheCategory) -> [CacheItem] { items.filter { $0.category == category } }

    func scanIfNeeded() {
        guard !started else { return }
        scan()
    }

    func scan() {
        started = true
        task?.cancel()
        items = []
        selection = []
        confirmingMove = false
        isScanning = true
        task = Task { [weak self] in
            let trash = await Task.detached { Self.trashSize() }.value
            self?.trashBytes = trash
            self?.containers = await Task.detached { Self.containerData() }.value
            self?.dockerRows = await Task.detached { Self.dockerUsage() }.value
            self?.snapshots = await Task.detached { LocalSnapshots.list() }.value
            for await item in Self.stream() {
                if Task.isCancelled { break }
                guard let self else { return }
                self.items.append(item)
                self.items.sort { $0.bytes > $1.bytes }
            }
            self?.isScanning = false
            if !Task.isCancelled {
                self?.hasScanned = true
                self?.persist()
            }
        }
    }

    /// Kazanılabilir alan kartı için son sonucu yazar.
    private func persist() {
        ReclaimStore.save(.cache, bytes: items.reduce(0) { $0 + $1.bytes })
        ReclaimStore.save(.trash, bytes: trashBytes)
        var sizes = ["Önbellek": items.reduce(0) { $0 + $1.bytes }, "Çöp Kutusu": trashBytes]
        for container in containers { if let bytes = container.bytes { sizes[container.name] = bytes } }
        FolderLog.record(sizes)
    }

    func toggle(_ item: CacheItem) {
        if selection.contains(item.url) { selection.remove(item.url) } else { selection.insert(item.url) }
        confirmingMove = false
    }

    func selectAll(in category: CacheCategory) {
        let urls = items(in: category).map(\.url)
        if urls.allSatisfy({ selection.contains($0) }) { selection.subtract(urls) } else { selection.formUnion(urls) }
        confirmingMove = false
    }

    /// Seçilenleri Çöp Kutusu'na taşır. Geri alınabilir.
    func moveSelectedToTrash() {
        confirmingMove = false
        var moved: UInt64 = 0
        var failed = 0
        for item in items where selection.contains(item.url) {
            guard TrashGuard.canTrash(item.url) else { failed += 1; continue }
            do {
                try TrashGuard.trash(item.url, bytes: item.bytes, source: "Önbellek")
                moved += item.bytes
            } catch { failed += 1 }
        }
        let chosen = selection
        items.removeAll { chosen.contains($0.url) && !FileManager.default.fileExists(atPath: $0.url.path) }
        selection = []
        trashBytes += moved
        persist()
        notice = failed == 0
            ? "\(formatBytes(moved)) Çöp Kutusu'na taşındı. Alan, Çöp Kutusu boşalınca açılır."
            : "\(formatBytes(moved)) taşındı. \(failed) öğe taşınamadı."
    }

    /// Finder ile Çöp Kutusu'nu boşaltır. KALICIDIR.
    func emptyTrash() {
        confirmingEmpty = false
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&error)
        if let error {
            notice = "Çöp Kutusu boşaltılamadı: \(error[NSAppleScript.errorMessage] as? String ?? "bilinmeyen hata")"
        } else {
            trashBytes = 0
            persist()
            notice = "Çöp Kutusu boşaltıldı."
        }
    }

    // MARK: Tarama

    /// Arka plan bildirimi için önbellek toplamını okur. Listeyi ve seçimi değiştirmez.
    nonisolated static func totalCacheBytes() -> UInt64 {
        candidates().reduce(0) { $0 + FileSizer.size(of: $1.0) }
    }

    private nonisolated static func containerData() -> [ContainerData] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var found: [(String, URL)] = []
        let groups = home.appendingPathComponent("Library/Group Containers")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: groups.path)) ?? []
        for name in names where name.lowercased().contains("orbstack") { found.append(("OrbStack", groups.appendingPathComponent(name))) }
        for (label, relative) in [("OrbStack", ".orbstack"), ("Docker Desktop", "Library/Containers/com.docker.docker"), ("Spotlight dizini", "Library/Metadata")] {
            let url = home.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: url.path) { found.append((label, url)) }
        }
        let sized = found.compactMap { label, url -> ContainerData? in
            // OrbStack disk imajı data/data.img.raw dosyasıdır. Okunamıyorsa Tam Disk Erişimi eksiktir.
            let image = url.appendingPathComponent("data/data.img.raw")
            if url.path.contains("Group Containers") {
                let size = (try? image.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize
                return ContainerData(name: label, url: url, bytes: size.map { UInt64($0) })
            }
            let bytes = FileSizer.size(of: url)
            return bytes >= 1 << 20 ? ContainerData(name: label, url: url, bytes: bytes) : nil
        }
        return (sized + mailData(home: home) + DeveloperData.displayOnlyEntries(home: home)).sorted { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
    }

    /// Mail verisi korumalıdır. Klasör listelenemiyorsa Tam Disk Erişimi eksiktir ve boyut nil olur.
    private nonisolated static func mailData(home: URL) -> [ContainerData] {
        let mail = home.appendingPathComponent("Library/Mail")
        guard FileManager.default.fileExists(atPath: mail.path) else { return [] }
        let readable = (try? FileManager.default.contentsOfDirectory(atPath: mail.path)) != nil
        return [ContainerData(name: "Mail", url: mail, bytes: readable ? FileSizer.size(of: mail) : nil)]
    }

    /// `docker system df` çıktısını okur. Docker kapalıysa veya kurulu değilse boş döner. En çok 8 saniye bekler.
    nonisolated static func dockerExecutable() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "\(home)/.orbstack/bin/docker"]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    nonisolated static func dockerUsage() -> [DockerRow] {
        guard let path = dockerExecutable() else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["system", "df", "--format", "{{json .}}"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return parseDockerUsage(String(decoding: data, as: UTF8.self))
    }

    nonisolated static func parseDockerUsage(_ output: String) -> [DockerRow] {
        output.split(separator: "\n").compactMap { line in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = object["Type"] as? String, let size = object["Size"] as? String else { return nil }
            return DockerRow(type: type, size: size, reclaimable: object["Reclaimable"] as? String ?? "")
        }
    }

    private nonisolated static func trashSize() -> UInt64 {
        FileSizer.size(of: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
    }

    private nonisolated static func stream() -> AsyncStream<CacheItem> {
        AsyncStream { continuation in
            let worker = Task.detached {
                for (url, category) in candidates() {
                    if Task.isCancelled { break }
                    let bytes = FileSizer.size(of: url)
                    if bytes > 0 { continuation.yield(CacheItem(url: url, category: category, bytes: bytes)) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    private nonisolated static func candidates() -> [(URL, CacheCategory)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        func children(_ relative: String, _ category: CacheCategory, skipApple: Bool = false) -> [(URL, CacheCategory)] {
            let dir = home.appendingPathComponent(relative)
            let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            return urls
                .filter { !(skipApple && $0.lastPathComponent.hasPrefix("com.apple.")) && $0.lastPathComponent != "local.molebar" }
                .map { ($0, category) }
        }
        func single(_ relative: String, _ category: CacheCategory) -> [(URL, CacheCategory)] {
            let url = home.appendingPathComponent(relative)
            return FileManager.default.fileExists(atPath: url.path) ? [(url, category)] : []
        }
        return DeveloperData.trashable.flatMap { single($0, .dev) }
            + children("Library/Caches", .app, skipApple: true)
            + children("Library/Logs", .logs)
            + children(".cache", .dev)
            + children("Library/Developer/Xcode/DerivedData", .dev)
            + single(".npm/_cacache", .dev)
            + single(".gradle/caches", .dev)
            + single(".cargo/registry", .dev)
            + single(".cocoapods", .dev)
            + single(".bun/install/cache", .dev)
            + single(".pnpm-store", .dev)
            + single("Library/Developer/Xcode/iOS DeviceSupport", .dev)
            + single("Library/Developer/CoreSimulator/Caches", .dev)
    }
}

struct CachePage: View {
    @ObservedObject var cleaner: CacheCleaner

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Önbellek ve Çöp Kutusu").font(.title2.weight(.semibold))
                Spacer()
                if cleaner.isScanning { ProgressView().controlSize(.small) }
                Button { cleaner.scan() } label: { Image(systemName: "arrow.clockwise") }
                    .glassButton()
                    .disabled(cleaner.isScanning)
                    .help("Yeniden tara")
            }
            trashCard
            if !cleaner.containers.isEmpty || !cleaner.dockerRows.isEmpty || !cleaner.snapshots.isEmpty { containerCard }
            if let notice = cleaner.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                GlassGroup(spacing: 12) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(CacheCategory.allCases, id: \.self) { category in
                            let rows = cleaner.items(in: category)
                            if !rows.isEmpty { section(category, rows) }
                        }
                        if cleaner.items.isEmpty {
                            Text(cleaner.isScanning ? "Taranıyor..." : "Listelenecek önbellek bulunamadı.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .glassCard()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .shadowSafeScroll()
            footer
        }
        .padding(24)
        .onAppear { cleaner.scanIfNeeded() }
    }

    private var trashCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text("Çöp Kutusu").font(.subheadline.weight(.semibold))
                Text(formatBytes(cleaner.trashBytes)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            if cleaner.confirmingEmpty {
                Text("Kalıcı silinir, geri alınamaz.").font(.caption).foregroundStyle(.red)
                Button("Boşalt") { cleaner.emptyTrash() }.glassProminentButton()
                Button("Vazgeç") { cleaner.confirmingEmpty = false }.glassButton()
            } else {
                Button("Çöp Kutusu'nu boşalt") { cleaner.confirmingEmpty = true }
                    .glassButton()
                    .disabled(cleaner.trashBytes == 0)
            }
        }
        .padding(16)
        .glassCard()
    }

    private var containerTotal: UInt64 { cleaner.containers.reduce(0) { $0 + ($1.bytes ?? 0) } }

    /// Salt okunur. MoleBar konteyner verisini silmez, çünkü imajlar ve birimler geri alınamaz.
    private var containerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "shippingbox", title: "Konteyner verisi", trailing: containerTotal == 0 ? "" : formatBytes(containerTotal))
            ForEach(cleaner.containers) { item in
                HStack {
                    Text(item.name).font(.subheadline)
                    Spacer(minLength: 8)
                    Text(item.bytes.map(formatBytes) ?? "Okunamadı (Tam Disk Erişimi)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if !cleaner.dockerRows.isEmpty {
                Divider().opacity(0.4)
                Text("Docker (docker system df)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(cleaner.dockerRows) { row in
                    HStack {
                        Text(row.type).font(.caption)
                        Spacer(minLength: 8)
                        Text("\(row.size) · geri kazanılabilir \(row.reclaimable)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if cleaner.containers.contains(where: { $0.name == "Mail" }) {
                Text("Mail: Mail'de iletileri seçip İleti > İlişikleri Sil ile yer açabilirsiniz. Ek iletiden kalıcı çıkar. MoleBar Mail verisine dokunmaz.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if cleaner.containers.contains(where: { $0.name == "Spotlight dizini" }) {
                Text("Spotlight dizini: Boyut anormalse `sudo mdutil -E /` dizini yeniden kurar. MoleBar dokunmaz.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if cleaner.containers.contains(where: { DeveloperData.displayOnly.map(\.label).contains($0.name) }) {
                Text("Xcode arşivleri, simülatör cihazları ve iOS yedekleri: Xcode > Window > Organizer, Devices and Simulators veya Finder ile yönetin. MoleBar dokunmaz.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let oldest = cleaner.snapshots.map(\.date).min() {
                Divider().opacity(0.4)
                Text("Yerel Time Machine anlık görüntüleri").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack {
                    Text("\(cleaner.snapshots.count) adet").font(.caption)
                    Spacer(minLength: 8)
                    Text("en eskisi \(oldest.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text("Boyutu okunamaz. macOS alan gerekince bunları kendisi siler. Elle silmek için komutu kopyalayın ve Terminal'de çalıştırın. MoleBar çalıştırmaz.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("En eskisini silme komutunu kopyala") {
                    if let snapshot = cleaner.snapshots.min(by: { $0.date < $1.date }) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(LocalSnapshots.deleteCommand(for: snapshot), forType: .string)
                        cleaner.notice = "Komut panoya kopyalandı. Terminal'de çalıştırın."
                    }
                }
                .glassButton()
                .controlSize(.small)
            }
            Text("MoleBar bunu silmez. İmajlar ve birimler geri alınamaz. Boyut, diskte gerçekten ayrılan alandır. İçeriği görmek için komutu çalıştırın.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("docker system df") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("docker system df", forType: .string)
                cleaner.notice = "Komut panoya kopyalandı. Terminal'de çalıştırın."
            }
            .glassButton()
            .controlSize(.small)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func section(_ category: CacheCategory, _ rows: [CacheItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                CardHeader(symbol: "internaldrive", title: category.rawValue, trailing: formatBytes(rows.reduce(0) { $0 + $1.bytes }))
                Button(rows.allSatisfy({ cleaner.selection.contains($0.url) }) ? "Seçimi kaldır" : "Hepsini seç") {
                    cleaner.selectAll(in: category)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            }
            ForEach(rows) { item in
                HStack(spacing: 8) {
                    Image(systemName: cleaner.selection.contains(item.url) ? "checkmark.square.fill" : "square")
                        .foregroundStyle(cleaner.selection.contains(item.url) ? Color.accentColor : Color.secondary)
                    Text(item.name).font(.subheadline).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(formatBytes(item.bytes)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { cleaner.toggle(item) }
            }
        }
        .padding(16)
        .glassCard()
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 10) {
            Text(cleaner.selection.isEmpty ? "Öğe seçin." : "\(cleaner.selection.count) öğe · \(formatBytes(cleaner.selectedBytes))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            if cleaner.confirmingMove {
                Text("Çöp Kutusu'na taşınacak.").font(.caption)
                Button("Taşı") { cleaner.moveSelectedToTrash() }.glassProminentButton()
                Button("Vazgeç") { cleaner.confirmingMove = false }.glassButton()
            } else {
                Button { cleaner.confirmingMove = true } label: { Label("Çöp Kutusu'na taşı", systemImage: "trash") }
                    .glassButton()
                    .disabled(cleaner.selection.isEmpty)
            }
        }
        Text("Önbellekler uygulamalar tarafından yeniden üretilir. Taşıma geri alınabilir ama alan yalnızca Çöp Kutusu boşalınca açılır. Apple sistem önbellekleri listelenmez.")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
