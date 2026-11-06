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

    /// Çöp Kutusu'na taşıma yalnızca ev klasörünün ikinci düzeyinden itibaren ve harici disklerde açıktır.
    /// Ev klasörünün doğrudan alt öğeleri, yasak yollar ve medya kütüphaneleri (.photoslibrary vb.) korunur.
    static func canTrash(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
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
