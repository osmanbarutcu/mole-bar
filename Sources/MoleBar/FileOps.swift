import Foundation

/// Çöp Kutusu'na taşıma kuralları. Tüm sayfalar aynı korumayı kullanır.
enum TrashGuard {
    /// Ev klasöründe yasak yollar. Posta, mesaj, anahtar zinciri, iCloud ve kimlik bilgileri taşınamaz.
    static let protectedHomePrefixes = [
        "Library/Mail", "Library/Messages", "Library/Keychains", "Library/Mobile Documents",
        "Library/CloudStorage", "Library/Safari", "Library/Accounts", "Library/Calendars",
        "Library/Contacts", "Library/Photos", "Library/Suggestions", "Library/Biome",
        "Library/Group Containers", "Library/Application Support/AddressBook",
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
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return UInt64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        var total: UInt64 = 0
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return 0 }
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true { continue }
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

    static func add(_ record: MoveRecord) {
        let all = Array(([record] + load()).prefix(limit))
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: key) }
    }
}

extension TrashGuard {
    /// Öğeyi Çöp Kutusu'na taşır ve geçmişe yazar. Tüm sayfalar bu işlevi kullanır.
    static func trash(_ url: URL, bytes: UInt64 = 0, source: String) throws {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        MoveLog.add(MoveRecord(
            id: UUID(), date: Date(), name: url.lastPathComponent,
            originalPath: url.path, trashedPath: (result as URL?)?.path,
            bytes: bytes, source: source
        ))
    }
}
