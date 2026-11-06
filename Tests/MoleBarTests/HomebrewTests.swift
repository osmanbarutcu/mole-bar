import Foundation
import Testing
@testable import MoleBar

struct HomebrewTests {
    private let sample = Data("""
    {"formulae":[
      {"name":"aom","installed_versions":["3.13.1"],"current_version":"3.15.3","pinned":false,"pinned_version":null},
      {"name":"node","installed_versions":["22.1.0","21.0.0"],"current_version":"22.2.0","pinned":true,"pinned_version":"22.1.0"}
    ],
    "casks":[
      {"name":"raycast","installed_versions":"1.80.0","current_version":"1.81.0"}
    ]}
    """.utf8)

    @Test func parsesFormulaeAndCasks() {
        let updates = Homebrew.parse(sample)
        #expect(updates.map(\.name) == ["aom", "node", "raycast"])
        #expect(updates.filter(\.isCask).map(\.name) == ["raycast"])
    }

    @Test func usesLatestInstalledVersion() {
        let updates = Homebrew.parse(sample)
        #expect(updates[0].installed == "3.13.1")
        #expect(updates[1].installed == "22.1.0")
        #expect(updates[2].installed == "1.80.0")
        #expect(updates[0].latest == "3.15.3")
    }

    @Test func marksPinnedFormulae() {
        let updates = Homebrew.parse(sample)
        #expect(!updates[0].isPinned)
        #expect(updates[1].isPinned)
    }

    @Test func badInputGivesEmptyList() {
        #expect(Homebrew.parse(Data("bozuk".utf8)).isEmpty)
        #expect(Homebrew.parse(Data("{}".utf8)).isEmpty)
    }

    @Test func upgradeCommandsAreCopyOnly() {
        #expect(Homebrew.upgradeCommand(for: nil) == "brew upgrade")
        #expect(Homebrew.upgradeCommand(for: "aom") == "brew upgrade aom")
    }

    @Test func rejectsUnsafeNamesInCommands() {
        #expect(Homebrew.upgradeCommand(for: "x; rm -rf ~") == "brew upgrade")
    }
}
