import Foundation
import Testing
@testable import MoleBar

struct FolderGrowthTests {
    private let mb: UInt64 = 1 << 20

    @Test func sameDaySampleReplacesPrevious() {
        let first = FolderLog.merge([], sizes: ["Önbellek": 100 * mb], day: "2026-11-01")
        let second = FolderLog.merge(first, sizes: ["Önbellek": 150 * mb], day: "2026-11-01")
        #expect(second.count == 1)
        #expect(second[0].sizes["Önbellek"] == 150 * mb)
    }

    @Test func newDayAppendsAndLimitKeepsNewest() {
        var samples: [FolderSample] = []
        for index in 1...95 {
            samples = FolderLog.merge(samples, sizes: ["A": UInt64(index) * mb], day: String(format: "2026-%02d-%02d", 1 + index / 28, 1 + index % 28))
        }
        #expect(samples.count == 90)
        #expect(samples.last?.sizes["A"] == 95 * mb)
    }

    @Test func growthListsOnlyPositiveChangesAboveThresholdLargestFirst() {
        let samples = [
            FolderSample(day: "2026-10-20", sizes: ["Önbellek": 100 * mb, "Mail": 500 * mb, "Docker": 900 * mb, "Küçük": 10 * mb]),
            FolderSample(day: "2026-11-05", sizes: ["Önbellek": 400 * mb, "Mail": 450 * mb, "Docker": 1500 * mb, "Küçük": 12 * mb])
        ]
        let growth = FolderGrowth.compute(samples)
        #expect(growth.map(\.name) == ["Docker", "Önbellek"])
        #expect(growth.first?.bytes == 600 * mb)
        #expect(growth.first?.days == 16)
    }

    @Test func nameMissingInOldestSampleIsSkipped() {
        let samples = [
            FolderSample(day: "2026-10-20", sizes: ["Önbellek": 100 * mb]),
            FolderSample(day: "2026-11-05", sizes: ["Önbellek": 100 * mb, "Yeni": 900 * mb])
        ]
        #expect(FolderGrowth.compute(samples).isEmpty)
    }

    @Test func fewerThanTwoSamplesGivesNoGrowth() {
        #expect(FolderGrowth.compute([]).isEmpty)
        #expect(FolderGrowth.compute([FolderSample(day: "2026-11-05", sizes: ["A": 900 * mb])]).isEmpty)
    }
}
