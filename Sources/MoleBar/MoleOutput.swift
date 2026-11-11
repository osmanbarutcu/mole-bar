import Foundation

struct PreviewLine: Identifiable {
    enum Kind { case section, item, ok, note }
    let id: Int
    let kind: Kind
    let text: String
    var size: String?
}

/// Mole çıktısını satır satır ayrıştırır. Yan etkisi yoktur.
/// Biçim: "➤ Bölüm", "→ Öğe, 2.92GB dry", "✓ Tamam", "◎ Not",
/// "Potential space: 9.40GB | Items: 317 | Categories: 32". Tanınmayan satır yalnızca ham kuyruğa girer.
/// Gerçek çıktı örnekleri: Tests/MoleBarTests/Fixtures (Mole 1.32.0).
struct MoleOutput {
    static let tailLimit = 14

    private(set) var lines: [PreviewLine] = []
    private(set) var rawTail: [String] = []
    private(set) var summary: String?
    private(set) var currentSection = ""
    private var buffer = ""

    /// Özet satırı veya en az bir tanınan satır varsa çıktı tanınmıştır.
    var isRecognized: Bool { summary != nil || !lines.isEmpty }

    private static let sizePattern = try? NSRegularExpression(
        pattern: #"^(.*?),?\s+(\d+(?:\.\d+)?\s?(?:B|KB|MB|GB|TB))(?:\s+dry)?$"#
    )

    /// Gelen parçayı tampona ekler ve tamamlanan satırları işler. Yarım satır tamponda kalır.
    mutating func consume(_ chunk: String) {
        var parts = (buffer + chunk).replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        buffer = parts.removeLast()
        for raw in parts { handle(Self.clean(raw)) }
    }

    /// Süreç bitince tamponda kalan son satırı işler.
    mutating func flush() {
        guard !buffer.isEmpty else { return }
        handle(Self.clean(buffer))
        buffer = ""
    }

    private mutating func handle(_ line: String) {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard let first = text.first else { return }
        rawTail = Array((rawTail + [text]).suffix(Self.tailLimit))
        if text.contains("Potential space:") { summary = text; return }
        let body = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        switch first {
        case "➤":
            currentSection = body
            append(.section, body)
        case "→":
            let (name, size) = Self.splitSize(body)
            append(.item, name, size: size)
        case "✓":
            append(.ok, body)
        case "◎", "☞":
            append(.note, body)
        default:
            break
        }
    }

    private mutating func append(_ kind: PreviewLine.Kind, _ text: String, size: String? = nil) {
        lines = lines + [PreviewLine(id: lines.count, kind: kind, text: text, size: size)]
    }

    static func splitSize(_ text: String) -> (name: String, size: String?) {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = sizePattern?.firstMatch(in: text, range: range),
              let nameRange = Range(match.range(at: 1), in: text),
              let sizeRange = Range(match.range(at: 2), in: text) else { return (text, nil) }
        return (String(text[nameRange]), String(text[sizeRange]))
    }

    static func clean(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[a-zA-Z]", with: "", options: .regularExpression)
    }

    // MARK: Görünüm yardımcıları

    /// Özeti etiket ve değer çiftlerine ayırır. Bilinen etiketler Türkçeye çevrilir.
    static func summaryParts(_ summary: String) -> [(label: String, value: String)] {
        summary.components(separatedBy: "|").compactMap { part in
            let pieces = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pieces.count == 2 else { return nil }
            return (label: translate(pieces[0]), value: pieces[1])
        }
    }

    /// Özetin ilk değeri (temizlenebilir alan). Bulunamazsa boş metin.
    static func summaryValue(_ summary: String) -> String {
        summary.components(separatedBy: "|").first?
            .split(separator: ":", maxSplits: 1).dropFirst().first?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// Satırları bölüm başlıklarına göre gruplar. İlk bölümden önceki satırlar atlanır.
    static func sections(_ lines: [PreviewLine]) -> [(title: String, rows: [PreviewLine])] {
        lines.reduce(into: [(title: String, rows: [PreviewLine])]()) { result, line in
            if line.kind == .section {
                result.append((title: line.text, rows: []))
            } else if !result.isEmpty {
                result[result.count - 1].rows.append(line)
            }
        }
    }

    private static func translate(_ label: String) -> String {
        switch label {
        case "Potential space": return L("Temizlenebilir alan (tahmini)")
        case "Items": return L("Öğe")
        case "Categories": return L("Kategori")
        default: return label
        }
    }
}
