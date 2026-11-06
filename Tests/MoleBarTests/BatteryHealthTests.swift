import Foundation
import Testing
@testable import MoleBar

struct BatteryHealthTests {
    private func json(_ info: String) -> Data {
        Data(#"{"SPPowerDataType":[{"_name":"x"},{"sppower_battery_health_info":\#(info)}]}"#.utf8)
    }

    @Test func readsCapacityWithPercentPrefix() {
        let data = json(#"{"sppower_battery_health":"Good","sppower_battery_health_maximum_capacity":"%88"}"#)
        #expect(BatteryHealth.parse(data) == BatteryHealth(maximumCapacity: 88, condition: "İyi"))
    }

    @Test func readsCapacityWithPercentSuffix() {
        let data = json(#"{"sppower_battery_health":"Normal","sppower_battery_health_maximum_capacity":"92%"}"#)
        #expect(BatteryHealth.parse(data)?.maximumCapacity == 92)
    }

    @Test func returnsNilWhenThereIsNoBattery() {
        #expect(BatteryHealth.parse(Data(#"{"SPPowerDataType":[{"_name":"x"}]}"#.utf8)) == nil)
        #expect(BatteryHealth.parse(Data("bozuk".utf8)) == nil)
    }

    @Test func translatesKnownConditions() {
        #expect(BatteryHealth.conditionText("Poor") == "Zayıf")
        #expect(BatteryHealth.conditionText("Service Recommended") == "Servis önerilir")
        #expect(BatteryHealth.conditionText("Bilinmeyen") == "Bilinmeyen")
    }

    @Test func warnsBelowEightyPercent() {
        #expect(BatteryHealth(maximumCapacity: 79, condition: "Orta").needsAttention)
        #expect(!BatteryHealth(maximumCapacity: 80, condition: "İyi").needsAttention)
    }
}
