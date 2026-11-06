import Foundation
import Testing
@testable import MoleBar

struct SecurityStatusTests {
    @Test func fileVaultOutputs() {
        #expect(SecurityCheck.parse(.fileVault, output: "FileVault is On.\n") == .on)
        #expect(SecurityCheck.parse(.fileVault, output: "FileVault is Off.\n") == .off)
    }

    @Test func gatekeeperOutputs() {
        #expect(SecurityCheck.parse(.gatekeeper, output: "assessments enabled\n") == .on)
        #expect(SecurityCheck.parse(.gatekeeper, output: "assessments disabled\n") == .off)
    }

    @Test func firewallOutputs() {
        #expect(SecurityCheck.parse(.firewall, output: "Firewall is enabled. (State = 1)\n") == .on)
        #expect(SecurityCheck.parse(.firewall, output: "Firewall is enabled. (State = 2)\n") == .on)
        #expect(SecurityCheck.parse(.firewall, output: "Firewall is disabled. (State = 0)\n") == .off)
    }

    @Test func sipOutputs() {
        #expect(SecurityCheck.parse(.sip, output: "System Integrity Protection status: enabled.\n") == .on)
        #expect(SecurityCheck.parse(.sip, output: "System Integrity Protection status: disabled.\n") == .off)
    }

    @Test func sipCustomConfigurationIsNotReportedAsFullyOn() {
        let output = "System Integrity Protection status: unknown (Custom Configuration).\n"
        #expect(SecurityCheck.parse(.sip, output: output) == .unknown)
    }

    @Test func emptyOrUnrelatedOutputIsUnknown() {
        for setting in SecurityCheck.Setting.allCases {
            #expect(SecurityCheck.parse(setting, output: "") == .unknown)
            #expect(SecurityCheck.parse(setting, output: "komut bulunamadı") == .unknown)
        }
    }

    @Test func onlyOffNeedsAttention() {
        #expect(SecurityCheck.State.off.needsAttention)
        #expect(!SecurityCheck.State.on.needsAttention)
        #expect(!SecurityCheck.State.unknown.needsAttention)
    }

    @Test func everySettingHasTitleAndCommand() {
        for setting in SecurityCheck.Setting.allCases {
            #expect(!setting.title.isEmpty)
            #expect(setting.command.path.hasPrefix("/"))
        }
    }
}
