import Foundation
import Testing
@testable import MoleBar

@Suite("ErrorLog", .serialized)
struct ErrorLogTests {
    @Test("kayıt eklenir, en yeni başta durur, sınır 30")
    func addsAndLimits() {
        ErrorLog.clear()
        defer { ErrorLog.clear() }
        for index in 0..<35 { ErrorLog.add(source: "Test", message: "hata \(index)") }
        let all = ErrorLog.load()
        #expect(all.count == 30)
        #expect(all.first?.message == "hata 34")
    }

    @Test("olmayan dosyayı taşıma hatası günlüğe yazılır ve fırlatılır")
    func trashFailureIsLogged() {
        ErrorLog.clear()
        defer { ErrorLog.clear() }
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("molebar-yok-\(UUID().uuidString).txt")
        #expect(throws: (any Error).self) { try TrashGuard.trash(missing, source: "Test") }
        #expect(ErrorLog.load().first?.source == "Test")
    }
}
