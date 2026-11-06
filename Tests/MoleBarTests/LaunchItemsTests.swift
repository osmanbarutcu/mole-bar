import Foundation
import Testing
@testable import MoleBar

struct LaunchItemsTests {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("molebar-launch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ object: [String: Any], named name: String, in directory: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
        try data.write(to: directory.appendingPathComponent(name))
    }

    @Test func readsLabelProgramAndFlags() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write(["Label": "com.example.agent", "ProgramArguments": ["/usr/bin/true", "-x"], "RunAtLoad": true, "KeepAlive": true],
                  named: "com.example.agent.plist", in: dir)
        let items = LaunchItems.scan([(dir, .userAgent)], exists: { _ in true })
        #expect(items.count == 1)
        #expect(items[0].label == "com.example.agent")
        #expect(items[0].program == "/usr/bin/true")
        #expect(items[0].runAtLoad)
        #expect(items[0].keepAlive)
        #expect(!items[0].missing)
        #expect(items[0].scope == .userAgent)
    }

    @Test func programKeyWinsOverArgumentsAndKeepAliveDictCountsAsKeepAlive() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write(["Label": "a", "Program": "/bin/one", "ProgramArguments": ["/bin/two"], "KeepAlive": ["SuccessfulExit": false]],
                  named: "a.plist", in: dir)
        let item = LaunchItems.scan([(dir, .systemDaemon)], exists: { _ in true })[0]
        #expect(item.program == "/bin/one")
        #expect(item.keepAlive)
        #expect(!item.runAtLoad)
    }

    @Test func missingTargetIsFlaggedOnlyForAbsolutePaths() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write(["Label": "gone", "Program": "/yok/program"], named: "gone.plist", in: dir)
        try write(["Label": "relative", "ProgramArguments": ["python3"]], named: "relative.plist", in: dir)
        let items = LaunchItems.scan([(dir, .systemAgent)], exists: { _ in false })
        #expect(items.first { $0.label == "gone" }?.missing == true)
        #expect(items.first { $0.label == "relative" }?.missing == false)
    }

    @Test func labelFallsBackToFileNameAndMalformedFilesAreIgnored() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write(["ProgramArguments": ["/bin/ls"]], named: "adsiz.plist", in: dir)
        try Data("bozuk".utf8).write(to: dir.appendingPathComponent("bozuk.plist"))
        try Data("x".utf8).write(to: dir.appendingPathComponent("not.txt"))
        let items = LaunchItems.scan([(dir, .userAgent)], exists: { _ in true })
        #expect(items.map(\.label) == ["adsiz"])
    }

    @Test func itemsAreSortedByLabelCaseInsensitive() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["b", "A", "c"] { try write(["Label": name, "Program": "/bin/ls"], named: "\(name).plist", in: dir) }
        #expect(LaunchItems.scan([(dir, .userAgent)], exists: { _ in true }).map(\.label) == ["A", "b", "c"])
    }
}
