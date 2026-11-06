import Foundation
import Testing
@testable import MoleBar

@Suite("SystemInfo")
struct SystemInfoTests {
    @Test("açık kalma metni gün, saat ve dakikayı gösterir", arguments: [
        (90.0, "1 dk"), (3_700.0, "1 saat 1 dk"), (86_400.0 * 2 + 3_600 * 5, "2 gün 5 saat")
    ])
    func uptimeText(_ seconds: Double, _ expected: String) {
        #expect(SystemInfo.uptimeText(seconds) == expected)
    }

    @Test("yeniden başlatma uyarısı 30 günde başlar")
    func rebootHint() {
        let base = SystemInfo(battery: nil, thermal: .nominal, uptime: 0)
        var info = base
        info.uptime = 29 * 86_400
        #expect(!info.needsReboot)
        info.uptime = 30 * 86_400
        #expect(info.needsReboot)
    }

    @Test("pil metni durumu yansıtır")
    func batteryText() {
        let charging = BatteryInfo(percent: 80, isCharging: true, onACPower: true, minutesRemaining: nil, cycleCount: nil)
        let onBattery = BatteryInfo(percent: 50, isCharging: false, onACPower: false, minutesRemaining: 125, cycleCount: nil)
        let plugged = BatteryInfo(percent: 100, isCharging: false, onACPower: true, minutesRemaining: nil, cycleCount: nil)
        #expect(SystemInfo.batteryText(charging) == "%80 · şarj oluyor")
        #expect(SystemInfo.batteryText(onBattery) == "%50 · 2 sa 5 dk kaldı")
        #expect(SystemInfo.batteryText(plugged) == "%100 · şarjda")
    }

    @Test("gerçek açılış süresi pozitif ve makul")
    func realUptime() {
        let seconds = SystemInfo.readUptime()
        #expect(seconds > 0)
        #expect(seconds < 3650 * 86_400)
    }
}
