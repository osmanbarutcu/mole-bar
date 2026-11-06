import Foundation
import Testing
@testable import MoleBar

struct QuitPolicyTests {
    @Test func plainQuitRequestKeepsTheAppInTheMenuBar() {
        let policy = QuitPolicy()
        #expect(policy.decision() == .keepInMenuBar)
    }

    @Test func explicitQuitFromThePanelTerminates() {
        let policy = QuitPolicy()
        policy.allowQuit()
        #expect(policy.decision() == .terminate)
    }

    @Test func systemPowerOffAndLogoutTerminate() {
        let policy = QuitPolicy()
        policy.systemIsEnding()
        #expect(policy.decision() == .terminate)
    }

    @Test func eachPolicyStartsFresh() {
        let first = QuitPolicy()
        first.allowQuit()
        #expect(QuitPolicy().decision() == .keepInMenuBar)
    }

    @Test func menuBarOnlyModeHidesTheDockIcon() {
        #expect(QuitPolicy.activationAfterKeepingInMenuBar == .accessory)
        #expect(QuitPolicy.activationWhenWindowOpens == .regular)
    }
}
