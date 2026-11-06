import Foundation
import Testing
@testable import MoleBar

@Suite("MoveRestore.restore")
struct MoveRestoreTests {
    private struct Fixture {
        let root: URL
        let trash: URL
        let original: URL
        let trashed: URL
        var record: MoveRecord {
            MoveRecord(id: UUID(), date: Date(), name: "a.bin", originalPath: original.path, trashedPath: trashed.path, bytes: 3, source: "Test")
        }
    }

    /// `root/.Trash/a.bin` taşınmış dosya, `root/proje/a.bin` özgün yol.
    private func makeFixture(trashedExists: Bool = true, parentExists: Bool = true) throws -> Fixture {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("molebar-restore-\(UUID().uuidString)")
        let trash = root.appendingPathComponent(".Trash")
        try fm.createDirectory(at: trash, withIntermediateDirectories: true)
        if parentExists { try fm.createDirectory(at: root.appendingPathComponent("proje"), withIntermediateDirectories: true) }
        let trashed = trash.appendingPathComponent("a.bin")
        if trashedExists { try Data("abc".utf8).write(to: trashed) }
        return Fixture(root: root, trash: trash, original: root.appendingPathComponent("proje/a.bin"), trashed: trashed)
    }

    @Test("dosya özgün yola döner ve Çöp Kutusu'ndan çıkar")
    func restores() throws {
        let f = try makeFixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        try MoveRestore.restore(f.record, isAllowed: { _ in true })
        #expect(FileManager.default.fileExists(atPath: f.original.path))
        #expect(!FileManager.default.fileExists(atPath: f.trashed.path))
    }

    @Test("hedefte aynı ad varsa üzerine yazmaz")
    func destinationExists() throws {
        let f = try makeFixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        try Data("yeni".utf8).write(to: f.original)
        #expect(throws: MoveRestore.Failure.destinationExists) { try MoveRestore.restore(f.record, isAllowed: { _ in true }) }
        #expect(try String(contentsOf: f.original, encoding: .utf8) == "yeni")
        #expect(FileManager.default.fileExists(atPath: f.trashed.path))
    }

    @Test("Çöp Kutusu'nda dosya yoksa hata verir")
    func trashedMissing() throws {
        let f = try makeFixture(trashedExists: false)
        defer { try? FileManager.default.removeItem(at: f.root) }
        #expect(throws: MoveRestore.Failure.trashedMissing) { try MoveRestore.restore(f.record, isAllowed: { _ in true }) }
    }

    @Test("üst klasör yoksa klasör oluşturmaz, hata verir")
    func parentMissing() throws {
        let f = try makeFixture(parentExists: false)
        defer { try? FileManager.default.removeItem(at: f.root) }
        #expect(throws: MoveRestore.Failure.parentMissing) { try MoveRestore.restore(f.record, isAllowed: { _ in true }) }
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("proje").path))
    }

    @Test("Çöp Kutusu dışındaki yol taşınmaz, kayıt sahte olsa bile")
    func notInTrash() throws {
        let f = try makeFixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let outside = f.root.appendingPathComponent("proje/b.bin")
        try Data("x".utf8).write(to: outside)
        let forged = MoveRecord(id: UUID(), date: Date(), name: "b.bin", originalPath: f.root.appendingPathComponent("proje/c.bin").path, trashedPath: outside.path, bytes: 1, source: "Test")
        #expect(throws: MoveRestore.Failure.notInTrash) { try MoveRestore.restore(forged, isAllowed: { _ in true }) }
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test("korumalı hedefe geri koymaz")
    func protectedDestination() throws {
        let f = try makeFixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        #expect(throws: MoveRestore.Failure.destinationNotAllowed) { try MoveRestore.restore(f.record, isAllowed: { _ in false }) }
        #expect(FileManager.default.fileExists(atPath: f.trashed.path))
    }

    @Test("kayıtta Çöp Kutusu yolu yoksa hata verir")
    func noTrashedPath() throws {
        let f = try makeFixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let record = MoveRecord(id: UUID(), date: Date(), name: "a", originalPath: f.original.path, trashedPath: nil, bytes: 0, source: "Test")
        #expect(throws: MoveRestore.Failure.noTrashedPath) { try MoveRestore.restore(record, isAllowed: { _ in true }) }
    }

    @Test("gerçek Çöp Kutusu: trashItem ile taşınan dosya geri alınır")
    func realTrashRoundTrip() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("molebar-real-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let file = dir.appendingPathComponent("gercek.bin")
        try Data("gercek".utf8).write(to: file)
        var result: NSURL?
        try fm.trashItem(at: file, resultingItemURL: &result)
        let record = MoveRecord(id: UUID(), date: Date(), name: "gercek.bin", originalPath: file.path, trashedPath: (result as URL?)?.path, bytes: 6, source: "Test")
        defer { if let path = record.trashedPath { try? fm.removeItem(atPath: path) } }
        #expect(record.trashedPath != nil)
        try MoveRestore.restore(record, isAllowed: { _ in true })
        #expect(try String(contentsOf: file, encoding: .utf8) == "gercek")
        #expect(!fm.fileExists(atPath: record.trashedPath ?? "/yok"))
    }
}
