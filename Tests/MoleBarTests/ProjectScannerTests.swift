import Foundation
import Testing
@testable import MoleBar

@Suite("ProjectScanner.scan")
struct ProjectScannerTests {
    private func makeRoot() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("molebar-proj-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func touch(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    @Test("manifest dosyası olan proje bulunur, olmayan atlanır")
    func requiresManifest() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try touch(root.appendingPathComponent("web/package.json"))
        try touch(root.appendingPathComponent("web/node_modules/a/index.js"))
        try touch(root.appendingPathComponent("app/Package.swift"))
        try touch(root.appendingPathComponent("app/.build/x.o"))
        try touch(root.appendingPathComponent("orphan/node_modules/b/index.js"))
        let found = ProjectScanner.scan(root: root, maxDepth: 4)
        let kinds = Set(found.map(\.kind))
        #expect(found.count == 2)
        #expect(kinds == ["node_modules", ".build"])
        #expect(found.allSatisfy { $0.project != "orphan" })
    }

    @Test("node_modules içindeki iç içe node_modules ayrıca listelenmez")
    func nestedIgnored() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try touch(root.appendingPathComponent("web/package.json"))
        try touch(root.appendingPathComponent("web/node_modules/pkg/package.json"))
        try touch(root.appendingPathComponent("web/node_modules/pkg/node_modules/z/index.js"))
        #expect(ProjectScanner.scan(root: root, maxDepth: 5).count == 1)
    }

    @Test("pyvenv.cfg olan .venv bulunur")
    func pythonVenv() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try touch(root.appendingPathComponent("api/.venv/pyvenv.cfg"))
        try touch(root.appendingPathComponent("api2/.venv/readme.txt"))
        let found = ProjectScanner.scan(root: root, maxDepth: 4)
        #expect(found.map(\.project) == ["api"])
    }

    @Test("derinlik sınırı aşılırsa bulunmaz")
    func depthLimit() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try touch(root.appendingPathComponent("a/b/c/d/package.json"))
        try touch(root.appendingPathComponent("a/b/c/d/node_modules/x.js"))
        #expect(ProjectScanner.scan(root: root, maxDepth: 3).isEmpty)
        #expect(ProjectScanner.scan(root: root, maxDepth: 5).count == 1)
    }

    @Test("manifest yoksa proje klasörünün tarihi kullanılır, tarih boş kalmaz")
    func lastActiveFallback() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try touch(root.appendingPathComponent("api/.venv/pyvenv.cfg"))
        let found = ProjectScanner.scan(root: root, maxDepth: 4)
        #expect(found.first?.lastActive != nil)
    }

    @Test("git commit günlüğü manifestten yeniyse etkinlik ona göre sayılır")
    func gitLogCounts() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = root.appendingPathComponent("web/package.json")
        let gitLog = root.appendingPathComponent("web/.git/logs/HEAD")
        try touch(manifest)
        try touch(gitLog)
        try touch(root.appendingPathComponent("web/node_modules/a.js"))
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        let recent = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: manifest.path)
        try FileManager.default.setAttributes([.modificationDate: recent], ofItemAtPath: gitLog.path)
        #expect(ProjectScanner.scan(root: root, maxDepth: 4).first?.lastActive == recent)
    }

    @Test("son etkinlik manifest tarihidir")
    func lastActive() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = root.appendingPathComponent("web/package.json")
        try touch(manifest)
        try touch(root.appendingPathComponent("web/node_modules/a.js"))
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: manifest.path)
        let found = ProjectScanner.scan(root: root, maxDepth: 4)
        #expect(found.first?.lastActive == old)
    }
}
