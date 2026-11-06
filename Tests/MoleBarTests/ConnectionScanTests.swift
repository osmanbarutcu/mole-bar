import Foundation
import Testing
@testable import MoleBar

struct ConnectionScanTests {
    private let sample = """
    p909
    cidentityservicesd
    f32
    n[fe80:28::c4f9:5a61:8ddc:a3b0]:1024->[fe80:28::ac6:6bb:4f8d:c795]:1024
    p1202
    cBrave Browser Helper
    f30
    n192.168.0.16:59323->140.82.114.25:443
    f31
    n192.168.0.16:59324->140.82.114.25:443
    f32
    n[::1]:58376->[::1]:5173
    f33
    n192.168.0.16:59330->151.101.1.140:443
    p77
    cnode
    f10
    n127.0.0.1:5000->127.0.0.1:5432
    f11
    n[2a00:1450:4001::200e]:443->[2001:db8::1]:50000
    """

    @Test func parsesProcessAndRemoteEndpoint() {
        let list = ConnectionScan.parse(sample)
        let brave = list.first { $0.pid == 1202 }
        #expect(brave?.process == "Brave Browser Helper")
        #expect(brave?.remotes.contains("140.82.114.25:443") == true)
    }

    @Test func dropsLocalAndLinkLocalPeers() {
        let list = ConnectionScan.parse(sample)
        #expect(!list.contains { $0.pid == 909 })
        #expect(!list.contains { $0.pid == 77 && $0.remotes.contains("127.0.0.1:5432") })
        #expect(list.flatMap(\.remotes).allSatisfy { !$0.hasPrefix("::1") })
    }

    @Test func countsConnectionsPerRemote() {
        let brave = ConnectionScan.parse(sample).first { $0.pid == 1202 }
        #expect(brave?.count == 3)
        #expect(brave?.remotes.first == "140.82.114.25:443")
    }

    @Test func sortsByConnectionCountDescending() {
        let counts = ConnectionScan.parse(sample).map(\.count)
        #expect(counts == counts.sorted(by: >))
    }

    @Test func privateAddressDetection() {
        for host in ["127.0.0.1", "10.1.2.3", "192.168.0.16", "172.16.0.1", "172.31.255.1", "169.254.1.1", "::1", "fe80::1", "fd00::1", "0.0.0.0"] {
            #expect(ConnectionScan.isLocalHost(host), "\(host) yerel sayılmadı")
        }
        for host in ["8.8.8.8", "172.32.0.1", "140.82.114.25", "2a00:1450:4001::200e"] {
            #expect(!ConnectionScan.isLocalHost(host), "\(host) yerel sayıldı")
        }
    }

    @Test func splitsIPv6AndIPv4Endpoints() {
        #expect(ConnectionScan.splitEndpoint("[2a00::1]:443")?.host == "2a00::1")
        #expect(ConnectionScan.splitEndpoint("[2a00::1]:443")?.port == "443")
        #expect(ConnectionScan.splitEndpoint("1.2.3.4:80")?.host == "1.2.3.4")
        #expect(ConnectionScan.splitEndpoint("bozuk") == nil)
    }
}
