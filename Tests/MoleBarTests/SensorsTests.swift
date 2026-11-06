import Foundation
import Testing
@testable import MoleBar

struct SensorsTests {
    private func floatBytes(_ value: Float) -> [UInt8] {
        withUnsafeBytes(of: value) { Array($0) }
    }

    @Test func decodesFloat() {
        let value = SMCValue.decode(type: "flt ", bytes: floatBytes(70.5))
        #expect(value == 70.5)
    }

    @Test func decodesFixedPointSP78() {
        // 0x2C80 = 44,5 (Intel sıcaklık biçimi, büyük bayt önce)
        #expect(SMCValue.decode(type: "sp78", bytes: [0x2C, 0x80]) == 44.5)
    }

    @Test func decodesFanSpeedFPE2() {
        // 0x12C0 >> 2 = 1200 dev/dk
        #expect(SMCValue.decode(type: "fpe2", bytes: [0x12, 0xC0]) == 1200)
    }

    @Test func decodesUnsignedBytes() {
        #expect(SMCValue.decode(type: "ui8 ", bytes: [2]) == 2)
        #expect(SMCValue.decode(type: "ui32", bytes: [0, 0, 6, 226]) == 1762)
    }

    @Test func rejectsUnknownTypeOrShortData() {
        #expect(SMCValue.decode(type: "zzzz", bytes: [1, 2]) == nil)
        #expect(SMCValue.decode(type: "flt ", bytes: [1]) == nil)
    }

    @Test func summaryTakesHottestCPUAndGPU() {
        let readings: [String: Double] = ["Tp01": 70.3, "Tp05": 68.7, "Te04": 58.8, "Tg0f": 62.3, "Tg0n": 63.8, "Tb00": 30]
        let summary = SensorSummary.make(readings)
        #expect(summary.cpu == 70.3)
        #expect(summary.gpu == 63.8)
    }

    @Test func summaryIgnoresImplausibleValues() {
        let readings: [String: Double] = ["Tp01": 0, "Tp05": -127, "Tg0f": 300, "Tp09": 55]
        let summary = SensorSummary.make(readings)
        #expect(summary.cpu == 55)
        #expect(summary.gpu == nil)
    }

    @Test func summaryHandlesIntelKeys() {
        let summary = SensorSummary.make(["TC0P": 61.0, "TG0P": 55.0])
        #expect(summary.cpu == 61)
        #expect(summary.gpu == 55)
    }

    @Test func sensorKeyFilterKeepsTemperatureKeysOnly() {
        #expect(SensorSummary.isCPUKey("Tp01"))
        #expect(SensorSummary.isCPUKey("Te04"))
        #expect(SensorSummary.isCPUKey("TC0P"))
        #expect(SensorSummary.isGPUKey("Tg0f"))
        #expect(SensorSummary.isGPUKey("TG0P"))
        #expect(!SensorSummary.isCPUKey("Tb00"))
        #expect(!SensorSummary.isCPUKey("FNum"))
    }
}
