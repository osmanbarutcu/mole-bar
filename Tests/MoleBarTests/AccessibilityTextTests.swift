import Foundation
import Testing
@testable import MoleBar

struct AccessibilityTextTests {
    @Test func percentIsRoundedAndSpelledOut() {
        #expect(A11y.percent(73.4) == "yüzde 73")
        #expect(A11y.percent(73.6) == "yüzde 74")
    }

    @Test func percentIsClampedToTheValidRange() {
        #expect(A11y.percent(-5) == "yüzde 0")
        #expect(A11y.percent(140) == "yüzde 100")
    }

    @Test func tileLabelNamesTheItemAndItsSize() {
        #expect(A11y.tile(name: "Library", bytes: 0, isDirectory: true).hasPrefix("Library, klasör"))
        #expect(A11y.tile(name: "film.mp4", bytes: 1_000_000, isDirectory: false).hasPrefix("film.mp4, dosya"))
    }
}
