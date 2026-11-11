import Foundation
import Testing
@testable import MoleBar

@Suite("CPUHogAlert")
struct CPUHogAlertTests {
    private let start = Date(timeIntervalSince1970: 0)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    @Test("süreç 5 dakika eşiğin üstünde kalınca bir kez bildirilir")
    func notifiesOnceAfterDuration() {
        var alert = CPUHogAlert()
        #expect(alert.evaluate([("ffmpeg", 150)], now: at(0)).isEmpty)
        #expect(alert.evaluate([("ffmpeg", 120)], now: at(299)).isEmpty)
        #expect(alert.evaluate([("ffmpeg", 95)], now: at(300)) == ["ffmpeg"])
        #expect(alert.evaluate([("ffmpeg", 99)], now: at(900)).isEmpty)
    }

    @Test("eşiğin altına inen süreç sayacı sıfırlar")
    func dropResets() {
        var alert = CPUHogAlert()
        _ = alert.evaluate([("node", 100)], now: at(0))
        _ = alert.evaluate([("node", 10)], now: at(200))
        #expect(alert.evaluate([("node", 100)], now: at(310)).isEmpty)
        #expect(alert.evaluate([("node", 100)], now: at(609)).isEmpty)
        #expect(alert.evaluate([("node", 100)], now: at(610)) == ["node"])
    }

    @Test("bildirilen süreç düşüp yeniden yükselirse yeniden bildirilir")
    func rearmsAfterDrop() {
        var alert = CPUHogAlert()
        _ = alert.evaluate([("x", 100)], now: at(0))
        #expect(alert.evaluate([("x", 100)], now: at(300)) == ["x"])
        _ = alert.evaluate([], now: at(400))
        _ = alert.evaluate([("x", 100)], now: at(500))
        #expect(alert.evaluate([("x", 100)], now: at(800)) == ["x"])
    }

    @Test("birden fazla süreç ayrı izlenir, sonuç adla sıralıdır")
    func multiple() {
        var alert = CPUHogAlert()
        _ = alert.evaluate([("b", 100), ("a", 100), ("c", 5)], now: at(0))
        #expect(alert.evaluate([("b", 100), ("a", 100), ("c", 5)], now: at(300)) == ["a", "b"])
    }

    @Test("eşik ve süre değiştirilebilir, eşik değeri dahildir")
    func customThreshold() {
        var alert = CPUHogAlert(threshold: 50, duration: 60)
        _ = alert.evaluate([("y", 50)], now: at(0))
        #expect(alert.evaluate([("y", 50)], now: at(60)) == ["y"])
    }

    @Test("bildirim metni süreç adını ve süreyi içerir")
    func message() {
        #expect(CPUHogAlert.body(for: ["ffmpeg"]) == "ffmpeg 5 dakikadır %90 üstü CPU kullanıyor. Süreçler sayfasından inceleyin.")
        #expect(CPUHogAlert.body(for: ["a", "b"]) == "a, b 5 dakikadır %90 üstü CPU kullanıyor. Süreçler sayfasından inceleyin.")
    }

    @Test("CPU bildirimi Süreçler sayfasını açar")
    func route() {
        #expect(NotificationRoute.section(for: "molebar.cpu") == .processes)
    }
}
