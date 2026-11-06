import Foundation
import Testing
@testable import MoleBar

@Suite("DuplicateFinder.plan")
struct DuplicatePlanTests {
    private let a = URL(fileURLWithPath: "/Volumes/D/a.bin")
    private let b = URL(fileURLWithPath: "/Volumes/D/b.bin")
    private let c = URL(fileURLWithPath: "/Volumes/D/c.bin")

    private func dates(_ map: [URL: Double]) -> (URL) -> Date {
        { Date(timeIntervalSince1970: map[$0] ?? 0) }
    }

    private func plan(_ files: [URL], keepOldest: Bool, times: [URL: Double], allowed: @escaping (URL) -> Bool = { _ in true }) -> [URL] {
        let group = DuplicateGroup(id: "g", size: 10, files: files)
        return DuplicateFinder.plan(groups: [group], keepOldest: keepOldest, canTrash: allowed, modified: dates(times)).map(\.url)
    }

    @Test("en eski kalır, diğerleri taşınır")
    func keepsOldest() {
        let moved = plan([a, b, c], keepOldest: true, times: [a: 300, b: 100, c: 200])
        #expect(Set(moved) == [a, c])
    }

    @Test("en yeni kalır, diğerleri taşınır")
    func keepsNewest() {
        let moved = plan([a, b, c], keepOldest: false, times: [a: 300, b: 100, c: 200])
        #expect(Set(moved) == [b, c])
    }

    @Test("her grupta en az bir kopya kalır")
    func alwaysKeepsOne() {
        let moved = plan([a, b, c], keepOldest: true, times: [a: 1, b: 1, c: 1])
        #expect(moved.count == 2)
    }

    @Test("korumalı yoldaki kopya taşınmaz")
    func skipsProtected() {
        let moved = plan([a, b], keepOldest: true, times: [a: 1, b: 2], allowed: { $0 != b })
        #expect(moved.isEmpty)
    }

    @Test("tek dosyalı grup taşıma üretmez")
    func singleFileGroup() {
        #expect(plan([a], keepOldest: true, times: [a: 1]).isEmpty)
    }

    @Test("bayt değeri grup boyutundan gelir")
    func bytesFromGroup() {
        let group = DuplicateGroup(id: "g", size: 42, files: [a, b])
        let result = DuplicateFinder.plan(groups: [group], keepOldest: true, canTrash: { _ in true }, modified: dates([a: 1, b: 2]))
        #expect(result.first?.bytes == 42)
    }
}
