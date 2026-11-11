import Foundation
import Testing
@testable import MoleBar

@Suite("LargeFileFinder çekirdeği")
struct LargeFileFinderTests {
    private func makeRoot() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("molebar-large-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ url: URL, bytes: Int) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: url)
    }

    @Test("uzantı türü büyük küçük harften bağımsız bulunur", arguments: [
        ("a.DMG", FileKind.image), ("b.sparsebundle", .image), ("c.tar", .archive), ("d.Zip", .archive),
        ("e.mov", .video), ("f.MKV", .video), ("g.txt", .other), ("noext", .other)
    ])
    func kinds(name: String, kind: FileKind) {
        #expect(FileKind.of(URL(fileURLWithPath: "/tmp/\(name)")) == kind)
    }

    @Test("klasör yolu ev klasörünü ~ ile kısaltır")
    func folderShortensHome() {
        let file = LargeFile(url: URL(fileURLWithPath: NSHomeDirectory() + "/Downloads/x.dmg"), bytes: 1)
        #expect(file.folder == "~/Downloads")
        #expect(file.name == "x.dmg")
        #expect(file.kind == .image)
    }

    @Test("gezinti eşiğin üstündeki dosyaları bulur, paket içini atlar")
    func walkFindsLargeFiles() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(root.appendingPathComponent("big.bin"), bytes: 200_000)
        try write(root.appendingPathComponent("sub/big2.iso"), bytes: 300_000)
        try write(root.appendingPathComponent("small.txt"), bytes: 10)
        try write(root.appendingPathComponent("Tool.app/Contents/huge.bin"), bytes: 400_000)

        var hits: [LargeFile] = []
        var lastProgress: (Int, Int)?
        LargeFileFinder.walk(root: root, limit: 100_000) { event in
            switch event {
            case .hit(let file): hits.append(file)
            case .progress(let count, let errors): lastProgress = (count, errors)
            }
        }
        #expect(Set(hits.map(\.name)) == ["big.bin", "big2.iso"])
        #expect(lastProgress?.0 == 3)
        #expect(lastProgress?.1 == 0)
    }

    @Test("olmayan kök yalnızca sıfır ilerleme bildirir")
    func walkMissingRoot() {
        var events = 0
        var hits = 0
        LargeFileFinder.walk(root: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"), limit: 1) { event in
            events += 1
            if case .hit = event { hits += 1 }
        }
        #expect(hits == 0)
        #expect(events <= 1)
    }

    @Test("ilk N listesi büyükten küçüğe sıralı kalır ve sınırı aşmaz")
    func topListCaps() {
        func file(_ name: String, _ bytes: UInt64) -> LargeFile { LargeFile(url: URL(fileURLWithPath: "/tmp/\(name)"), bytes: bytes) }
        var list: [LargeFile] = []
        for (name, bytes) in [("a", 5), ("b", 9), ("c", 1), ("d", 7)] as [(String, UInt64)] {
            list = LargeFileFinder.inserting(file(name, bytes), into: list, cap: 3)
        }
        #expect(list.map(\.name) == ["b", "d", "a"])
    }
}
