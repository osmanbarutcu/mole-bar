import Foundation

struct ReleaseInfo: Equatable {
    let version: String
    let url: URL
}

/// Yeni sürüm denetimi. Yalnızca GitHub Releases'a tek bir GET isteği gönderir.
/// Varsayılan kapalıdır. İstek GitHub'a IP adresinizi gösterir. Hiçbir veri gönderilmez, hiçbir şey indirilmez.
enum UpdateCheck {
    static let endpoint = URL(string: "https://api.github.com/repos/osmanbarutcu/mole-bar/releases/latest")!
    static let interval: TimeInterval = 24 * 3_600
    static let enabledKey = "updateCheckEnabled"
    static let lastCheckKey = "lastUpdateCheck"

    /// Yanıtı çözer. Taslak, ön sürüm, bozuk yanıt ve GitHub dışı bağlantı nil verir.
    static func parse(_ data: Data) -> ReleaseInfo? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["draft"] as? Bool != true, object["prerelease"] as? Bool != true,
              let tag = object["tag_name"] as? String,
              let link = object["html_url"] as? String, let url = URL(string: link),
              url.scheme == "https", url.host == "github.com" else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return version.isEmpty ? nil : ReleaseInfo(version: version, url: url)
    }

    /// Sürümleri sayı sayı karşılaştırır (0.10.0 > 0.9.0). Çözülemeyen sürüm asla yeni sayılmaz.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ text: String) -> [Int]? {
            let numbers = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
            return numbers.contains(where: { $0 == nil }) || numbers.isEmpty ? nil : numbers.compactMap { $0 }
        }
        guard let new = parts(candidate), let old = parts(current) else { return false }
        for index in 0..<max(new.count, old.count) {
            let a = index < new.count ? new[index] : 0
            let b = index < old.count ? old[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    static func isDue(lastCheck: Date?, now: Date = Date()) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// 10 sn zaman aşımı. Ağ hatasında nil döner. Çerez ve önbellek kullanılmaz.
    static func fetchLatest() async -> ReleaseInfo? {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MoleBar/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parse(data)
    }
}
