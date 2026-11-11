import Foundation
import Testing
@testable import MoleBar

/// Fixture dosyaları gerçek `mo` 1.32.0 çıktısıdır (2026-11-12). Ev yolu `/Users/user` ile değiştirildi.
private func fixture(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)")
    return try String(contentsOf: url, encoding: .utf8)
}

@Suite("MoleOutput gerçek çıktı")
struct MoleOutputFixtureTests {
    @Test("mo clean --dry-run çıktısı bölüm, öğe ve özet olarak ayrışır")
    func cleanDryRun() throws {
        var parser = MoleOutput()
        parser.consume(try fixture("mo-clean-dry-run-1.32.0.txt"))
        parser.flush()

        #expect(parser.summary == "Potential space: 15.17GB | Items: 474 | Categories: 49")
        #expect(parser.isRecognized)
        let sections = MoleOutput.sections(parser.lines)
        #expect(sections.count == 15)
        #expect(sections.first?.title == "User essentials")
        let firstItem = sections.first?.rows.first
        #expect(firstItem?.kind == .item)
        #expect(firstItem?.text == "User app cache 113 items")
        #expect(firstItem?.size == "6.92GB")
        // Boyutu olmayan öğe adıyla kalır.
        #expect(parser.lines.contains { $0.text == "npm cache · would clean" && $0.size == nil })
        // ANSI renk kodu temizlenir.
        #expect(!parser.lines.contains { $0.text.contains("\u{1B}") })
        #expect(parser.currentSection == "Project artifacts")
    }

    @Test("mo clean özeti etiket ve değere ayrılır, etiket Türkçeye çevrilir")
    func cleanSummaryParts() throws {
        let parts = MoleOutput.summaryParts("Potential space: 15.17GB | Items: 474 | Categories: 49")
        #expect(parts.map(\.label) == ["Temizlenebilir alan (tahmini)", "Öğe", "Kategori"])
        #expect(parts.map(\.value) == ["15.17GB", "474", "49"])
        #expect(MoleOutput.summaryValue("Potential space: 15.17GB | Items: 474") == "15.17GB")
    }

    @Test("mo optimize --dry-run çıktısı bakım adımlarını sayar")
    func optimizeDryRun() throws {
        var parser = MoleOutput()
        parser.consume(try fixture("mo-optimize-dry-run-1.32.0.txt"))
        parser.flush()

        #expect(parser.summary == nil)
        #expect(parser.isRecognized)
        #expect(MoleOutput.sections(parser.lines).count == 14)
        // İlk satır "→ DRY RUN MODE" bölümden önce gelir, bölüm listesine girmez.
        let steps = MoleOutput.sections(parser.lines).flatMap(\.rows).filter { $0.kind == .item }
        #expect(steps.count == 25)
    }
}

@Suite("MoleOutput satır işleme")
struct MoleOutputLineTests {
    @Test("parça parça gelen satır birleşir")
    func chunkedLine() {
        var parser = MoleOutput()
        parser.consume("➤ Brow")
        #expect(parser.lines.isEmpty)
        parser.consume("sers\n  → Chrome cache 2 items, 456.4MB dry\n")
        #expect(parser.lines.map(\.text) == ["Browsers", "Chrome cache 2 items"])
        #expect(parser.lines.last?.size == "456.4MB")
    }

    @Test("satır başı karakteri yeni satır sayılır")
    func carriageReturn() {
        var parser = MoleOutput()
        parser.consume("✓ bir\r✓ iki\n")
        #expect(parser.lines.map(\.text) == ["bir", "iki"])
        #expect(parser.lines.allSatisfy { $0.kind == .ok })
    }

    @Test("son satır yeni satırsız biterse flush ile işlenir")
    func flushTail() {
        var parser = MoleOutput()
        parser.consume("◎ not")
        parser.flush()
        #expect(parser.lines.first?.kind == .note)
        #expect(parser.lines.first?.text == "not")
    }

    @Test("tanınmayan satır yalnızca ham kuyruğa girer, kuyruk 14 satırı aşmaz")
    func rawTailCapped() {
        var parser = MoleOutput()
        parser.consume((1...20).map { "satır \($0)" }.joined(separator: "\n") + "\n")
        #expect(parser.lines.isEmpty)
        #expect(parser.rawTail.count == 14)
        #expect(parser.rawTail.first == "satır 7")
        #expect(!parser.isRecognized)
    }

    @Test("boş satır yok sayılır, kimlikler sıralı artar")
    func idsIncrease() {
        var parser = MoleOutput()
        parser.consume("\n   \n➤ A\n☞ B\n")
        #expect(parser.lines.map(\.id) == [0, 1])
        #expect(parser.rawTail == ["➤ A", "☞ B"])
    }

    @Test("boyut biçimleri", arguments: [
        ("Safari cache, 4KB dry", "Safari cache", "4KB"),
        ("Homebrew lock files 50 items, 0B dry", "Homebrew lock files 50 items", "0B"),
        ("Disk image 1.5 TB", "Disk image", "1.5 TB"),
        ("Rust cargo cache, 99.6MB dry", "Rust cargo cache", "99.6MB"),
        ("Xcode runtime volumes · 3 unused", "Xcode runtime volumes · 3 unused", nil)
    ])
    func splitSize(text: String, name: String, size: String?) {
        let result = MoleOutput.splitSize(text)
        #expect(result.name == name)
        #expect(result.size == size)
    }

    @Test("bölümden önceki satırlar bölüm listesine girmez")
    func sectionsSkipPreamble() {
        let lines = [
            PreviewLine(id: 0, kind: .ok, text: "önce"),
            PreviewLine(id: 1, kind: .section, text: "A"),
            PreviewLine(id: 2, kind: .item, text: "x")
        ]
        let sections = MoleOutput.sections(lines)
        #expect(sections.count == 1)
        #expect(sections[0].rows.map(\.text) == ["x"])
    }

    @Test("bozuk özet parçası atlanır")
    func badSummaryPart() {
        #expect(MoleOutput.summaryParts("Potential space: 1GB | bozuk").count == 1)
        #expect(MoleOutput.summaryParts("Bilinmeyen: 3").first?.label == "Bilinmeyen")
        #expect(MoleOutput.summaryValue("bozuk") == "")
    }
}

@Suite("MoleCLI sürüm ve yol")
struct MoleCLITests {
    @Test("sürüm satırı ayrışır")
    func parseVersion() {
        #expect(MoleCLI.parseVersion("Mole version 1.32.0\nmacOS: 27.0.1\n") == "1.32.0")
        #expect(MoleCLI.parseVersion("mo 2.0.1-beta") == "2.0.1-beta")
        #expect(MoleCLI.parseVersion("Mole 1.32.0.") == "1.32.0")
        #expect(MoleCLI.parseVersion("bilinmeyen çıktı") == nil)
    }

    @Test("denenen sürüm tanınır, farklı sürüm uyarı verir")
    func testedVersion() {
        #expect(MoleCLI.isTested("1.32.0"))
        #expect(!MoleCLI.isTested("1.33.0"))
        #expect(!MoleCLI.isTested(nil))
    }

    @Test("ilk çalıştırılabilir aday yol seçilir")
    func resolvePath() {
        let found = MoleCLI.resolvePath(candidates: ["/nonexistent/mo", "/bin/ls"])
        #expect(found == "/bin/ls")
        #expect(MoleCLI.resolvePath(candidates: ["/nonexistent/mo"]) == nil)
    }
}
