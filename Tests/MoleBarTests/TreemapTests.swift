import CoreGraphics
import Foundation
import Testing
@testable import MoleBar

struct TreemapTests {
    private let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
    private let values: [Double] = [600, 300, 200, 100, 50, 25, 0, 10]

    @Test func tilesFillTheWholeArea() {
        let rects = Treemap.layout(values: values, in: bounds)
        let total = rects.reduce(0.0) { $0 + Double($1.width * $1.height) }
        #expect(abs(total - 400 * 300) < 1)
    }

    @Test func everyTileStaysInsideTheBounds() {
        for rect in Treemap.layout(values: values, in: bounds) where rect != .zero {
            #expect(rect.minX >= -0.001 && rect.minY >= -0.001)
            #expect(rect.maxX <= 400.001 && rect.maxY <= 300.001)
        }
    }

    @Test func tilesDoNotOverlap() {
        let rects = Treemap.layout(values: values, in: bounds).filter { $0 != .zero }
        for (i, a) in rects.enumerated() {
            for b in rects[(i + 1)...] {
                let overlap = a.intersection(b)
                #expect(overlap.isNull || overlap.width * overlap.height < 0.01)
            }
        }
    }

    @Test func areaFollowsValue() {
        let rects = Treemap.layout(values: values, in: bounds)
        let big = rects[0].width * rects[0].height
        let small = rects[4].width * rects[4].height
        #expect(big > small * 10)
        let expected = CGFloat(600.0 / 1285.0) * 400 * 300
        #expect(abs(big - expected) < 1)
    }

    @Test func zeroValuesGetNoTile() {
        let rects = Treemap.layout(values: values, in: bounds)
        #expect(rects[6] == .zero)
        #expect(rects.count == values.count)
    }

    @Test func emptyOrZeroInputGivesNoTiles() {
        #expect(Treemap.layout(values: [], in: bounds).isEmpty)
        #expect(Treemap.layout(values: [0, 0], in: bounds) == [.zero, .zero])
        #expect(Treemap.layout(values: [1], in: .zero) == [.zero])
    }
}
