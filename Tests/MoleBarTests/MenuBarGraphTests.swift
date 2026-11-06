import CoreGraphics
import Foundation
import Testing
@testable import MoleBar

struct MenuBarGraphTests {
    @Test func pushKeepsOnlyTheLatestValues() {
        var values: [Double] = []
        for value in 1...5 { values = MenuBarGraph.push(values, Double(value), limit: 3) }
        #expect(values == [3, 4, 5])
    }

    @Test func pointsSpanTheFullWidth() {
        let points = MenuBarGraph.points(values: [10, 20, 30, 40], width: 30, height: 12)
        #expect(points.count == 4)
        #expect(points.first?.x == 0)
        #expect(points.last?.x == 30)
    }

    @Test func heightFollowsValueFromTheBottom() {
        let points = MenuBarGraph.points(values: [0, 50, 100], width: 20, height: 10)
        #expect(points[0].y == 0)
        #expect(points[1].y == 5)
        #expect(points[2].y == 10)
    }

    @Test func outOfRangeValuesAreClamped() {
        let points = MenuBarGraph.points(values: [-20, 250], width: 20, height: 10)
        #expect(points[0].y == 0)
        #expect(points[1].y == 10)
    }

    @Test func fewerThanTwoValuesGiveNoLine() {
        #expect(MenuBarGraph.points(values: [], width: 20, height: 10).isEmpty)
        #expect(MenuBarGraph.points(values: [50], width: 20, height: 10).isEmpty)
    }
}
