import Foundation
import Testing
@testable import MoleBar

struct MemoryPressureTests {
    @Test func sysctlLevelsMapToStates() {
        #expect(MemoryPressure(level: 1) == .normal)
        #expect(MemoryPressure(level: 2) == .warning)
        #expect(MemoryPressure(level: 4) == .critical)
    }

    @Test func unknownLevelFallsBackToNormal() {
        #expect(MemoryPressure(level: 0) == .normal)
        #expect(MemoryPressure(level: 99) == .normal)
    }

    @Test func labelsAreTurkishAndDistinct() {
        let labels = [MemoryPressure.normal, .warning, .critical].map(\.label)
        #expect(Set(labels).count == 3)
        #expect(MemoryPressure.critical.label == "Kritik")
    }

    @Test func onlyWarningAndCriticalNeedAttention() {
        #expect(!MemoryPressure.normal.needsAttention)
        #expect(MemoryPressure.warning.needsAttention)
        #expect(MemoryPressure.critical.needsAttention)
    }

    @Test func swapPercentHandlesZeroTotal() {
        #expect(SwapUsage(usedBytes: 0, totalBytes: 0).percent == 0)
        #expect(SwapUsage(usedBytes: 500, totalBytes: 1000).percent == 50)
    }
}

struct MemoryAlertTests {
    @Test func notifiesOnceWhenPressureTurnsCritical() {
        var alert = MemoryAlert()
        let r1 = alert.shouldNotify(.normal)
        #expect(!r1)
        let r2 = alert.shouldNotify(.warning)
        #expect(!r2)
        let r3 = alert.shouldNotify(.critical)
        #expect(r3)
        let r4 = alert.shouldNotify(.critical)
        #expect(!r4)
    }

    @Test func warningDoesNotResetTheAlert() {
        var alert = MemoryAlert()
        let r5 = alert.shouldNotify(.critical)
        #expect(r5)
        let r6 = alert.shouldNotify(.warning)
        #expect(!r6)
        let r7 = alert.shouldNotify(.critical)
        #expect(!r7)
    }

    @Test func normalPressureRearmsTheAlert() {
        var alert = MemoryAlert()
        let r8 = alert.shouldNotify(.critical)
        #expect(r8)
        let r9 = alert.shouldNotify(.normal)
        #expect(!r9)
        let r10 = alert.shouldNotify(.critical)
        #expect(r10)
    }
}
