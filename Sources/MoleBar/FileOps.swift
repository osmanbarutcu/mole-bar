import Foundation

/// Çöp Kutusu'na taşıma kuralları. Tüm sayfalar aynı korumayı kullanır.
enum TrashGuard {
    /// Ev klasöründe yasak yollar. Posta, mesaj, anahtar zinciri, iCloud ve kimlik bilgileri taşınamaz.
    static let protectedHomePrefixes = [
        "Library/Mail", "Library/Messages", "Library/Keychains", "Library/Mobile Documents",
        "Library/CloudStorage", "Library/Safari", "Library/Accounts", "Library/Calendars",
        "Library/Contacts", "Library/Photos", "Library/Suggestions", "Library/Biome",
        "Library/Group Containers", "Library/Application Support/AddressBook",
        "Library/Metadata", // Spotlight dizin verisi. mds kullanır, elle taşımak dizini bozar.
        ".ssh", ".gnupg", ".aws", ".kube", ".password-store"
    ]

    /// Yolu standartlaştırır ve sembolik bağlantıları çözer. Dosya yoksa en derin mevcut üst klasör çözülür, kalan kısım eklenir.
    static func resolved(_ url: URL) -> String {
        var existing = url.standardizedFileURL
        var rest: [String] = []
        while existing.path != "/", !FileManager.default.fileExists(atPath: existing.path) {
            rest.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
        var result = existing.resolvingSymlinksInPath()
        for part in rest { result.appendPathComponent(part) }
        return result.path
    }

    /// Çöp Kutusu'na taşıma yalnızca ev klasörünün ikinci düzeyinden itibaren ve harici disklerde açıktır.
    /// Ev klasörünün doğrudan alt öğeleri, yasak yollar ve medya kütüphaneleri (.photoslibrary vb.) korunur.
    static func canTrash(_ url: URL) -> Bool {
        // Sembolik bağlantılar çözülür. Aksi hâlde /Volumes/Macintosh HD/Users/... yolu ev klasörü korumasını atlatır.
        let path = resolved(url)
        let home = resolved(FileManager.default.homeDirectoryForCurrentUser)
        let mediaLibraries = [".photoslibrary", ".musiclibrary", ".tvlibrary", ".photolibrary"]
        if mediaLibraries.contains(where: { path.lowercased().contains($0) }) { return false }
        if path.hasPrefix(home + "/") {
            let relative = String(path.dropFirst(home.count + 1))
            if protectedHomePrefixes.contains(where: { relative == $0 || relative.hasPrefix($0 + "/") }) { return false }
            return relative.split(separator: "/").count >= 2
        }
        if path.hasPrefix("/Volumes/") {
            return path.dropFirst("/Volumes/".count).split(separator: "/").count >= 2
        }
        return false
    }
}

/// Dosya ve klasör boyutu (ayrılan bayt). Salt okunur.
enum FileSizer {
    static func size(of url: URL) -> UInt64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isDirectoryKey, .linkCountKey, .fileResourceIdentifierKey]
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return UInt64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        var total: UInt64 = 0
        // Sert bağlantılı dosya (örn. Spotlight dizini) bir kez sayılır. `du` aynı şekilde davranır.
        var seenLinks = Set<AnyHashable>()
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return 0 }
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true { continue }
            if (values?.linkCount ?? 1) > 1, let id = values?.fileResourceIdentifier as? AnyHashable, !seenLinks.insert(id).inserted { continue }
            total += UInt64(values?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}

/// Çöp Kutusu'na taşınan bir öğenin kaydı.
struct MoveRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let name: String
    let originalPath: String
    let trashedPath: String?
    let bytes: UInt64
    let source: String
}

/// Son taşımaların kalıcı listesi. Yalnızca UserDefaults'a yazar, dosyalara dokunmaz.
enum MoveLog {
    private static let key = "moveLog"
    private static let limit = 50

    static func load() -> [MoveRecord] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([MoveRecord].self, from: data)) ?? []
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }

    static func remove(id: UUID) {
        let rest = load().filter { $0.id != id }
        if let data = try? JSONEncoder().encode(rest) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func add(_ record: MoveRecord) {
        let all = Array(([record] + load()).prefix(limit))
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: key) }
    }
}

extension TrashGuard {
    /// Öğeyi Çöp Kutusu'na taşır ve geçmişe yazar. Tüm sayfalar bu işlevi kullanır.
    static func trash(_ url: URL, bytes: UInt64 = 0, source: String) throws {
        var result: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        } catch {
            ErrorLog.add(source: source, message: "\(url.lastPathComponent) taşınamadı: \(error.localizedDescription)")
            throw error
        }
        MoveLog.add(MoveRecord(
            id: UUID(), date: Date(), name: url.lastPathComponent,
            originalPath: url.path, trashedPath: (result as URL?)?.path,
            bytes: bytes, source: source
        ))
    }
}

/// Çöp Kutusu'na taşınan öğeyi özgün yoluna geri koyar. Hiçbir şeyin üzerine yazmaz, klasör oluşturmaz.
enum MoveRestore {
    enum Failure: Error, Equatable {
        case noTrashedPath, notInTrash, trashedMissing, destinationNotAllowed, destinationExists, parentMissing

        var message: String {
            switch self {
            case .noTrashedPath: return "Kayıtta Çöp Kutusu yolu yok. Finder'da arayın."
            case .notInTrash: return "Dosya Çöp Kutusu'nda değil. Geri alınmadı."
            case .trashedMissing: return "Dosya Çöp Kutusu'nda bulunamadı. Boşaltılmış olabilir."
            case .destinationNotAllowed: return "Özgün yol korumalı. Finder'dan elle geri alın."
            case .destinationExists: return "Özgün yolda aynı adlı öğe var. Üzerine yazılmadı."
            case .parentMissing: return "Özgün klasör artık yok. Geri alınmadı."
            }
        }
    }

    /// Kayıtlı yolun gerçekten bir Çöp Kutusu klasöründe olduğunu doğrular. Sahte kayıt başka dosyayı taşıyamaz.
    private static func isInTrash(_ path: String) -> Bool {
        let resolved = TrashGuard.resolved(URL(fileURLWithPath: path))
        return resolved.contains("/.Trash/") || resolved.contains("/.Trashes/")
    }

    static func restore(_ record: MoveRecord, isAllowed: (URL) -> Bool = TrashGuard.canTrash) throws {
        guard let trashedPath = record.trashedPath else { throw Failure.noTrashedPath }
        guard isInTrash(trashedPath) else { throw Failure.notInTrash }
        let fm = FileManager.default
        guard fm.fileExists(atPath: trashedPath) else { throw Failure.trashedMissing }
        let original = URL(fileURLWithPath: record.originalPath)
        guard isAllowed(original) else { throw Failure.destinationNotAllowed }
        guard !fm.fileExists(atPath: original.path) else { throw Failure.destinationExists }
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: original.deletingLastPathComponent().path, isDirectory: &isDirectory), isDirectory.boolValue
        else { throw Failure.parentMissing }
        try fm.moveItem(at: URL(fileURLWithPath: trashedPath), to: original)
    }
}

/// Son hataların kalıcı listesi. Taşıma hataları `TrashGuard.trash` içinden yazılır.
struct ErrorRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let source: String
    let message: String
}

enum ErrorLog {
    private static let key = "errorLog"
    private static let limit = 30

    static func load() -> [ErrorRecord] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ErrorRecord].self, from: data)) ?? []
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }

    static func add(source: String, message: String) {
        let record = ErrorRecord(id: UUID(), date: Date(), source: source, message: message)
        let all = Array(([record] + load()).prefix(limit))
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: key) }
    }
}
