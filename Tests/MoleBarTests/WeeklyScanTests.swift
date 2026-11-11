import Foundation
import Testing
@testable import MoleBar

@Suite("WeeklyScan")
struct WeeklyScanTests {
    private let now = Date(timeIntervalSince1970: 30 * 86_400)

    @Test("ayar açık, düşük güç kapalı ve 7 gün geçtiyse tarama zamanı gelmiştir")
    func due() {
        let old = now.addingTimeInterval(-7 * 86_400 - 1)
        #expect(WeeklyScan.isDue(enabled: true, lowPower: false, last: old, now: now))
        #expect(WeeklyScan.isDue(enabled: true, lowPower: false, last: nil, now: now))
    }

    @Test("ayar kapalı, düşük güç açık veya 7 gün dolmadıysa tarama yapılmaz")
    func notDue() {
        let recent = now.addingTimeInterval(-7 * 86_400)
        let old = now.addingTimeInterval(-8 * 86_400)
        #expect(!WeeklyScan.isDue(enabled: false, lowPower: false, last: old, now: now))
        #expect(!WeeklyScan.isDue(enabled: true, lowPower: true, last: old, now: now))
        #expect(!WeeklyScan.isDue(enabled: true, lowPower: false, last: recent, now: now))
    }

    @Test("bildirim metni tüm parçaları içerir")
    func fullBody() {
        let body = WeeklyScan.body(cleanable: "15.17GB", cacheBytes: 6_000_000_000, staleProjectBytes: 2_000_000_000,
                                   growth: "Önbellek 1 GB büyüdü.")
        #expect(body.hasPrefix("Temizlenebilir alan: 15.17GB. Önbellek: "))
        #expect(body.contains("90 günden eski proje çıktıları: "))
        #expect(body.contains("Önbellek 1 GB büyüdü. "))
        #expect(body.hasSuffix("Araçlar sekmesinden inceleyin. Hiçbir şey silinmedi."))
    }

    @Test("proje çıktısı yoksa ve büyüme yoksa o parçalar yazılmaz")
    func shortBody() {
        let body = WeeklyScan.body(cleanable: "", cacheBytes: 0, staleProjectBytes: 0, growth: nil)
        #expect(!body.contains("proje"))
        #expect(!body.contains("Temizlenebilir"))
        #expect(body.hasPrefix("Önbellek: "))
    }

    @Test("önbellek eşiği yalnızca eşik açıksa ve aşıldıysa uyarır")
    func cacheThreshold() {
        #expect(WeeklyScan.exceedsCacheLimit(cacheBytes: 5_000_000_000, limitGB: 5))
        #expect(!WeeklyScan.exceedsCacheLimit(cacheBytes: 4_999_999_999, limitGB: 5))
        #expect(!WeeklyScan.exceedsCacheLimit(cacheBytes: 99_000_000_000, limitGB: 0))
    }
}
