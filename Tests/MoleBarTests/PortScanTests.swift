import Foundation
import Testing
@testable import MoleBar

struct PortScanTests {
    private let sample = """
    p907
    cControlCenter
    Lit
    f9
    tIPv4
    PTCP
    n*:7000
    f10
    tIPv6
    PTCP
    n*:7000
    p1063
    collama
    Lit
    f3
    tIPv4
    PTCP
    n127.0.0.1:11434
    p2067
    cnode
    Lit
    f20
    tIPv6
    PTCP
    n[::1]:3000
    f21
    tIPv4
    PTCP
    n192.168.1.20:8080
    """

    @Test func parsesProcessPortAndScope() throws {
        let ports = PortScan.parse(sample)
        let ollama = try #require(ports.first { $0.process == "ollama" })
        #expect(ollama.pid == 1063)
        #expect(ollama.port == 11434)
        #expect(ollama.scope == .local)
        #expect(ollama.address == "127.0.0.1")
    }

    @Test func wildcardIsExposedToAllInterfaces() throws {
        let center = try #require(PortScan.parse(sample).first { $0.process == "ControlCenter" })
        #expect(center.scope == .all)
        #expect(center.address == "*")
    }

    @Test func ipv6LoopbackIsLocalAndOtherAddressIsInterface() throws {
        let ports = PortScan.parse(sample)
        #expect(ports.first { $0.port == 3000 }?.scope == .local)
        #expect(ports.first { $0.port == 3000 }?.address == "::1")
        #expect(ports.first { $0.port == 8080 }?.scope == .interface)
    }

    @Test func ipv4AndIpv6DuplicatesCollapse() {
        let ports = PortScan.parse(sample).filter { $0.port == 7000 }
        #expect(ports.count == 1)
    }

    @Test func widestExposureComesFirstThenByPort() {
        let ports = PortScan.parse(sample)
        #expect(ports.first?.scope == .all)
        #expect(ports.map(\.port) == [7000, 8080, 3000, 11434])
    }

    @Test func garbageAndEmptyGiveNoPorts() {
        #expect(PortScan.parse("").isEmpty)
        #expect(PortScan.parse("bozuk\nçıktı\nn:::").isEmpty)
    }

    @Test func detailTextHasNoThousandsSeparator() {
        let port = ListeningPort(pid: 25746, process: "OrbStack Helper", address: "*", port: 8001, scope: .all)
        #expect(port.detail == "PID 25746 · *:8001")
        #expect(!port.detail.contains("."))
    }

    @Test func exposedCountOnlyCountsAllInterfaces() {
        #expect(PortScan.exposedCount(PortScan.parse(sample)) == 1)
    }
}
