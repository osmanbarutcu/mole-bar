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
