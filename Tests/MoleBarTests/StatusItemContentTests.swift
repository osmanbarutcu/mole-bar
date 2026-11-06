import Foundation
import Testing
@testable import MoleBar

struct StatusItemContentTests {
    @Test func textModeShowsOnlyTheBarText() {
        let content = StatusItemContent.resolve(displayMode: "text", barText: "CPU 12%", graphLabel: "12%")
        #expect(content == StatusItemContent(title: "CPU 12%", showsIcon: false, showsGraph: false))
    }

    @Test func iconModeHasNoTitle() {
        let content = StatusItemContent.resolve(displayMode: "icon", barText: "CPU 12%", graphLabel: "12%")
        #expect(content == StatusItemContent(title: "", showsIcon: true, showsGraph: false))
    }

    @Test func graphModeShowsGraphWithItsLabel() {
        let content = StatusItemContent.resolve(displayMode: "graph", barText: "CPU 12%", graphLabel: "73%")
        #expect(content == StatusItemContent(title: "73%", showsIcon: false, showsGraph: true))
    }

    @Test func unknownModeFallsBackToText() {
        let content = StatusItemContent.resolve(displayMode: "zzz", barText: "x", graphLabel: "y")
        #expect(content.title == "x")
        #expect(!content.showsIcon && !content.showsGraph)
    }

    @Test func customStatusItemIsOffByDefault() {
        #expect(!StatusItemController.isEnabled(defaults: UserDefaults(suiteName: "molebar.test.\(UUID().uuidString)")!))
    }
}
