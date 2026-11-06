import Foundation

/// Xcode ve cihaz verisi yolları. Ev klasörüne göreli yazılır.
enum DeveloperData {
    /// Yeniden üretilebilir. Önbellek listesine girer, Çöp Kutusu'na taşınabilir.
    static let trashable = [
        "Library/Developer/Xcode/watchOS DeviceSupport",
        "Library/Developer/Xcode/tvOS DeviceSupport",
        "Library/Developer/Xcode/UserData/Previews",
        "Library/Developer/XCPGDevices",
        // Paket yöneticisi önbellekleri. Bir sonraki derlemede yeniden indirilir.
        "go/pkg/mod",
        ".cargo/git",
        ".nuget/packages",
        ".composer/cache",
        ".yarn/berry/cache",
        ".local/share/pnpm/store"
    ]

    /// Geri üretilemez veya başka araç gerektirir. Yalnızca gösterilir, MoleBar silmez.
    static let displayOnly: [(label: String, relative: String)] = [
        ("Xcode arşivleri", "Library/Developer/Xcode/Archives"),
        ("Simülatör cihazları", "Library/Developer/CoreSimulator/Devices"),
        ("iOS/iPadOS yedekleri", "Library/Application Support/MobileSync/Backup")
    ]

    /// Salt okunur boyut. Klasör okunamıyorsa (izin yok) nil döner. 1 MB altı listelenmez.
    static func displayOnlyEntries(home: URL) -> [ContainerData] {
        displayOnly.compactMap { label, relative in
            let url = home.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let readable = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
            guard readable else { return ContainerData(name: label, url: url, bytes: nil) }
            let bytes = FileSizer.size(of: url)
            return bytes >= 1 << 20 ? ContainerData(name: label, url: url, bytes: bytes) : nil
        }
    }
}
