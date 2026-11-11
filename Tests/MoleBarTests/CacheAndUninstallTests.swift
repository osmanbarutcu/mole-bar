import Foundation
import Testing
@testable import MoleBar

private func makeRoot(_ prefix: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func touch(_ url: URL, bytes: Int = 1) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 2, count: bytes).write(to: url)
}

@Suite("CacheCleaner aday listesi")
struct CacheCandidateTests {
    @Test("Apple ve MoleBar önbellekleri atlanır, diğerleri kategorisiyle listelenir")
    func candidates() throws {
        let home = try makeRoot("molebar-cache")
        defer { try? FileManager.default.removeItem(at: home) }
        try touch(home.appendingPathComponent("Library/Caches/com.apple.Safari/x"))
        try touch(home.appendingPathComponent("Library/Caches/local.molebar/x"))
        try touch(home.appendingPathComponent("Library/Caches/com.google.Chrome/x"))
        try touch(home.appendingPathComponent("Library/Logs/com.apple.Thing/x"))
        try touch(home.appendingPathComponent(".cache/pip/x"))
        try touch(home.appendingPathComponent(".npm/_cacache/x"))

        let found = Dictionary(uniqueKeysWithValues: CacheCleaner.candidates(home: home).map { ($0.0.lastPathComponent, $0.1) })
        #expect(found["com.google.Chrome"] == .app)
        #expect(found["com.apple.Safari"] == nil)
        #expect(found["local.molebar"] == nil)
        // Günlüklerde Apple öğeleri de listelenir.
        #expect(found["com.apple.Thing"] == .logs)
        #expect(found["pip"] == .dev)
        #expect(found["_cacache"] == .dev)
    }

    @Test("olmayan klasörler boş liste verir")
    func emptyHome() throws {
        let home = try makeRoot("molebar-cache-empty")
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(CacheCleaner.candidates(home: home).isEmpty)
    }
}

@Suite("CacheCleaner seçim")
struct CacheSelectionTests {
    private let a = URL(fileURLWithPath: "/tmp/a"), b = URL(fileURLWithPath: "/tmp/b")

    @Test("tek öğe seçimi açılır ve kapanır")
    func toggle() {
        let once = CacheCleaner.toggled([], a)
        #expect(once == [a])
        #expect(CacheCleaner.toggled(once, a).isEmpty)
    }

    @Test("kategoride hepsi seçiliyse kaldırılır, değilse hepsi eklenir")
    func selectAll() {
        #expect(CacheCleaner.selectingAll([a, b], in: [a]) == [a, b])
        #expect(CacheCleaner.selectingAll([a, b], in: [a, b]).isEmpty)
        let other = URL(fileURLWithPath: "/tmp/c")
        #expect(CacheCleaner.selectingAll([a], in: [a, other]) == [other])
    }

    @Test("seçili boyut yalnızca seçilenleri toplar")
    func selectedBytes() {
        let items = [CacheItem(url: a, category: .app, bytes: 10), CacheItem(url: b, category: .dev, bytes: 5)]
        #expect(CacheCleaner.bytes(of: items, selected: [b]) == 5)
        #expect(CacheCleaner.bytes(of: items, selected: []) == 0)
    }
}

@Suite("AppUninstaller tarama")
struct AppUninstallerScanTests {
    private func makeApp(_ root: URL, _ name: String, id: String?) throws {
        let contents = root.appendingPathComponent("\(name).app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundleName": name]
        if let id { plist["CFBundleIdentifier"] = id }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    @Test("Apple ve MoleBar uygulamaları listelenmez, .app olmayanlar atlanır")
    func findApps() throws {
        let root = try makeRoot("molebar-apps")
        defer { try? FileManager.default.removeItem(at: root) }
        try makeApp(root, "Editor", id: "com.example.editor")
        try makeApp(root, "Safari", id: "com.apple.Safari")
        try makeApp(root, "MoleBar", id: "local.molebar")
        try makeApp(root, "NoID", id: nil)
        try touch(root.appendingPathComponent("readme.txt"))

        let apps = AppUninstaller.findApps(roots: [root, root.appendingPathComponent("missing")])
        #expect(Set(apps.map(\.name)) == ["Editor", "NoID"])
        #expect(apps.first { $0.name == "Editor" }?.bundleID == "com.example.editor")
        #expect(apps.first { $0.name == "NoID" }?.bundleID == nil)
    }

    @Test("artıklar kimlik ve ad ile bulunur, büyükten küçüğe sıralanır")
    func findLeftovers() throws {
        let library = try makeRoot("molebar-lib")
        defer { try? FileManager.default.removeItem(at: library) }
        try touch(library.appendingPathComponent("Application Support/com.example.editor/db"), bytes: 50_000)
        try touch(library.appendingPathComponent("Preferences/com.example.editor.plist"), bytes: 10)
        try touch(library.appendingPathComponent("Caches/Editor/c"), bytes: 20_000)
        try touch(library.appendingPathComponent("Caches/Other/c"))

        let app = AppEntry(url: URL(fileURLWithPath: "/Applications/Editor.app"), name: "Editor", bundleID: "com.example.editor")
        let found = AppUninstaller.findLeftovers(for: app, library: library)
        #expect(found.map(\.url.lastPathComponent) == ["com.example.editor", "Editor", "com.example.editor.plist"])
        #expect(found[0].bytes >= found[1].bytes)
    }

    @Test("kimliği olmayan uygulama yalnızca ad ile aranır")
    func leftoversWithoutID() throws {
        let library = try makeRoot("molebar-lib2")
        defer { try? FileManager.default.removeItem(at: library) }
        try touch(library.appendingPathComponent("Logs/Tool/log"))
        let app = AppEntry(url: URL(fileURLWithPath: "/Applications/Tool.app"), name: "Tool", bundleID: nil)
        #expect(AppUninstaller.findLeftovers(for: app, library: library).map(\.url.lastPathComponent) == ["Tool"])
    }
}
