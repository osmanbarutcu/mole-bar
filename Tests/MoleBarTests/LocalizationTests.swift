import Foundation
import Testing
@testable import MoleBar

/// İngilizce tablonun kaynakla uyumunu denetler. Ekran gerekmez.
/// Kural: SwiftUI sabit metni ve `L("…")` anahtarı tabloda olmalı. Tabloda kaynakta olmayan anahtar kalmamalı.
private enum LocalizationSource {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func table(_ language: String) throws -> [String: String] {
        let url = root.appendingPathComponent("Resources/\(language).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return plist as? [String: String] ?? [:]
    }

    static let sources: [String] = {
        let dir = root.appendingPathComponent("Sources/MoleBar")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        // Yorum satırları atlanır. Belgelerdeki örnek çağrılar anahtar sayılmaz.
        return names.filter { $0.hasSuffix(".swift") }.sorted().compactMap {
            try? String(contentsOf: dir.appendingPathComponent($0), encoding: .utf8)
        }.map { text in
            text.components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
        }
    }()

    private static let literal = #""((?:[^"\\]|\\.)*)""#

    static func matches(_ pattern: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: pattern)
        return sources.flatMap { text in
            regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
                Range(match.range(at: 1), in: text).map { unescape(String(text[$0])) }
            }
        }
    }

    static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: #"\""#, with: "\"").replacingOccurrences(of: #"\n"#, with: "\n")
            .replacingOccurrences(of: #"\\"#, with: "\\")
    }

    /// SwiftUI'nin tablodan kendiliğinden çevirdiği sabit metinler. Değişkenli metinler `L()` kullanır.
    static var swiftUILiterals: Set<String> {
        let calls = #"(?:\bText|\bButton|\bToggle|\bLabel|\bPicker|\bStepper|\.help|\.accessibilityLabel|\bSection|\bLink)\(\s*"#
        return Set(matches(calls + literal).filter { !$0.contains("\\(") && $0.rangeOfCharacter(from: .letters) != nil })
    }

    static var lKeys: Set<String> { Set(matches(#"\bL\(\s*"# + literal)) }

    static var allLiterals: Set<String> { Set(matches(literal)) }

    static func specifiers(_ text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:ll|l|h)?[@dDiuUxXfeEgGcsp]"#)
        // "%%" yüzde işaretidir, belirteç değildir. "%.0f%% full" içinde "% f" sanılmasın.
        let text = text.replacingOccurrences(of: "%%", with: "")
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
            .map { $0.replacingOccurrences(of: #"\d+\$"#, with: "", options: .regularExpression) }
            .sorted()
    }
}

@Suite("Yerelleştirme")
struct LocalizationTests {
    @Test("tablolar okunur")
    func tablesParse() throws {
        #expect(try !LocalizationSource.table("en").isEmpty)
        _ = try LocalizationSource.table("tr")
    }

    @Test("her SwiftUI sabit metninin İngilizcesi var")
    func swiftUICoverage() throws {
        let table = try LocalizationSource.table("en")
        let missing = LocalizationSource.swiftUILiterals.subtracting(table.keys).sorted()
        #expect(missing.isEmpty, "Eksik: \(missing)")
    }

    @Test("her L() anahtarının İngilizcesi var ve biçim belirteçleri aynı")
    func lKeyCoverage() throws {
        let table = try LocalizationSource.table("en")
        let missing = LocalizationSource.lKeys.filter { table[$0] == nil }.sorted()
        #expect(missing.isEmpty, "Eksik: \(missing)")
        for key in LocalizationSource.lKeys {
            guard let value = table[key] else { continue }
            #expect(LocalizationSource.specifiers(key) == LocalizationSource.specifiers(value), "Belirteç farkı: \(key)")
        }
    }

    @Test("tabloda kaynakta olmayan anahtar yok")
    func noStaleKeys() throws {
        // İç içe metindeki `L("…")` anahtarlarını genel tırnak taraması kaçırır, ayrıca eklenir.
        let used = LocalizationSource.allLiterals.union(LocalizationSource.lKeys)
        let stale = Set(try LocalizationSource.table("en").keys).subtracting(used).sorted()
        #expect(stale.isEmpty, "Kullanılmayan: \(stale)")
    }

    @Test("çeviri yoksa anahtar döner, değişken yerleşir, yüzde işareti korunur")
    func helper() {
        #expect(L("Bilinmeyen metin") == "Bilinmeyen metin")
        #expect(L("%d satır", 3) == "3 satır")
        #expect(L("Eşik %90") == "Eşik %90")
    }
}
