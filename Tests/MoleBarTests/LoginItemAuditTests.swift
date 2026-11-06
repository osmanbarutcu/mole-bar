import Foundation
import Testing
@testable import MoleBar

@Suite("LoginItemAudit.stale")
struct LoginItemAuditTests {
    private func makeDir(_ plists: [String: [String: Any]]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("molebar-la-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, content) in plists {
            let data = try PropertyListSerialization.data(fromPropertyList: content, format: .xml, options: 0)
            try data.write(to: dir.appendingPathComponent(name))
        }
        return dir
    }

    @Test("hedefi olmayan öğe listelenir, olan ve göreli yol atlanır")
    func detectsMissingTargets() throws {
        let dir = try makeDir([
            "a.plist": ["ProgramArguments": ["/Apps/Eksik.app/bin"]],
            "b.plist": ["Program": "/Apps/Var.app/bin"],
            "c.plist": ["ProgramArguments": ["python3", "x.py"]],
            "d.txt": ["Program": "/Apps/Eksik2"]
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        let result = LoginItemAudit.stale(in: dir, exists: { $0 == "/Apps/Var.app/bin" })
        #expect(result.map(\.name) == ["a"])
        #expect(result.first?.target == "/Apps/Eksik.app/bin")
    }

    @Test("olmayan klasör boş döner")
    func missingDirectory() {
        #expect(LoginItemAudit.stale(in: URL(fileURLWithPath: "/tmp/molebar-yok-\(UUID().uuidString)")).isEmpty)
    }
}
