import Foundation
import Testing
@testable import MoleBar

@Suite("DiskAnalyzer tarama çekirdeği")
struct DiskAnalyzerTests {
    private func makeRoot() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("molebar-analyze-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ url: URL, bytes: Int) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
    }

    @Test("alt öğeler klasör, dosya, paket ve bağlantı olarak ayrılır")
    func childrenKinds() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(root.appendingPathComponent("dir/a.bin"), bytes: 10)
        try write(root.appendingPathComponent("file.bin"), bytes: 10)
        try write(root.appendingPathComponent("Tool.app/Contents/Info.plist"), bytes: 10)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root.appendingPathComponent("dir"))

        let entries = Dictionary(uniqueKeysWithValues: try DiskAnalyzer.children(of: root).map { ($0.name, $0) })
        #expect(entries.count == 4)
        #expect(entries["dir"]?.isDirectory == true)
        #expect(entries["file.bin"]?.isDirectory == false)
        #expect(entries["Tool.app"]?.isPackage == true)
        #expect(entries["Tool.app"]?.isDirectory == false)
        // Bağlantı izlenmez: ne klasör ne paket sayılır.
        #expect(entries["link"]?.isDirectory == false)
        #expect(entries["link"]?.isPackage == false)
    }

    @Test("okunamayan klasör hata fırlatır")
    func childrenMissing() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        #expect(throws: (any Error).self) { try DiskAnalyzer.children(of: missing) }
    }

    @Test("klasör boyutu iç içe dosyaları toplar ve dosya sayar")
    func measureDirectory() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(root.appendingPathComponent("d/x.bin"), bytes: 100_000)
        try write(root.appendingPathComponent("d/sub/y.bin"), bytes: 50_000)
        let entry = DiskEntry(url: root.appendingPathComponent("d"), isDirectory: true)

        let measured = DiskAnalyzer.measure(entry)
        #expect(measured.items == 2)
        #expect(measured.bytes >= 150_000)
        #expect(measured.errors == 0)
        #expect(measured.url == entry.url)
    }

    @Test("tek dosya kendi boyutuyla ve 1 öğe olarak ölçülür")
    func measureFile() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("f.bin")
        try write(file, bytes: 20_000)
        let measured = DiskAnalyzer.measure(DiskEntry(url: file, isDirectory: false))
        #expect(measured.items == 1)
        #expect(measured.bytes >= 20_000)
    }

    @Test("paket klasör gibi içinden ölçülür")
    func measurePackage() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(root.appendingPathComponent("Tool.app/Contents/MacOS/bin"), bytes: 30_000)
        var entry = DiskEntry(url: root.appendingPathComponent("Tool.app"), isDirectory: false)
        entry.isPackage = true
        let measured = DiskAnalyzer.measure(entry)
        #expect(measured.items == 1)
        #expect(measured.bytes >= 30_000)
    }

    @Test("ölçülen sonuç listeye yazılır ve liste büyükten küçüğe sıralanır")
    func applySorts() {
        let a = URL(fileURLWithPath: "/tmp/a"), b = URL(fileURLWithPath: "/tmp/b")
        let entries = [DiskEntry(url: a, isDirectory: true), DiskEntry(url: b, isDirectory: true)]
        let result = DiskAnalyzer.applying(DiskMeasure(url: b, bytes: 500, items: 3, errors: 2), to: entries)
        #expect(result.map(\.url) == [b, a])
        #expect(result[0].bytes == 500)
        #expect(result[0].items == 3)
        #expect(result[0].sized)
        #expect(!result[1].sized)
    }

    @Test("listede olmayan sonuç listeyi değiştirmez")
    func applyUnknown() {
        let a = URL(fileURLWithPath: "/tmp/a")
        let entries = [DiskEntry(url: a, isDirectory: true)]
        let result = DiskAnalyzer.applying(DiskMeasure(url: URL(fileURLWithPath: "/tmp/z"), bytes: 1, items: 1, errors: 0), to: entries)
        #expect(result.map(\.url) == [a])
        #expect(!result[0].sized)
    }
}
