import Foundation
import Testing
@testable import MoleBar

@Suite("FileSizer.size")
struct FileSizerTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("molebar-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("olmayan yol 0 döner")
    func missingPath() {
        #expect(FileSizer.size(of: URL(fileURLWithPath: "/tmp/molebar-yok-\(UUID().uuidString)")) == 0)
    }

    @Test("klasör, içindeki dosyaların ayrılan boyutunu toplar")
    func directoryTotal() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(repeating: 1, count: 200_000).write(to: dir.appendingPathComponent("a.bin"))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("alt"), withIntermediateDirectories: true)
        try Data(repeating: 2, count: 300_000).write(to: dir.appendingPathComponent("alt/b.bin"))
        let size = FileSizer.size(of: dir)
        // Ayrılan boyut blok sınırına yuvarlanır, bu yüzden dosya toplamından küçük olamaz.
        #expect(size >= 500_000)
        #expect(size < 600_000)
    }

    @Test("sert bağlantılı dosya bir kez sayılır")
    func hardLinksCountOnce() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("a.bin")
        try Data(repeating: 4, count: 400_000).write(to: original)
        let single = FileSizer.size(of: dir)
        for index in 1...3 {
            try FileManager.default.linkItem(at: original, to: dir.appendingPathComponent("link\(index).bin"))
        }
        #expect(FileSizer.size(of: dir) == single)
    }

    @Test("tek dosya kendi boyutunu döner")
    func singleFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("x.bin")
        try Data(repeating: 3, count: 100_000).write(to: file)
        #expect(FileSizer.size(of: file) >= 100_000)
    }
}
