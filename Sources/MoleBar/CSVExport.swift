import AppKit
import Foundation
import UniformTypeIdentifiers

/// Tabloyu CSV metnine çevirir ve kullanıcının seçtiği yere kaydeder.
enum CSVExport {
    /// Elektronik tablo bu karakterlerle başlayan hücreyi formül olarak çalıştırır (CSV enjeksiyonu).
    /// Başına `'` konur. İndirilen dosyaların adları kötü niyetli olabilir.
    private static let formulaPrefixes: Set<Character> = ["=", "+", "-", "@", "\t", "\r"]

    static func escape(_ field: String) -> String {
        var value = field
        if let first = value.first, formulaPrefixes.contains(first) { value = "'" + value }
        let needsQuotes = value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func make(header: [String], rows: [[String]]) -> String {
        ([header] + rows).map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    /// Kaydetme penceresini açar. Dosya yalnızca kullanıcı yol seçince yazılır. Başarıda dosya adını döndürür.
    @MainActor
    static func save(_ text: String, suggestedName: String) -> String? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url.lastPathComponent
        } catch {
            return nil
        }
    }
}
