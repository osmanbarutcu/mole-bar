import Foundation
import SystemConfiguration
import Testing
@testable import MoleBar

struct NetworkInterfacesTests {
    private let types = [
        "en0": kSCNetworkInterfaceTypeIEEE80211 as String,
        "en5": kSCNetworkInterfaceTypeEthernet as String
    ]

    @Test func buildsWifiEthernetAndVpnInOrder() {
        let records: [NetworkInterfaces.Record] = [
            ("utun4", "10.8.0.2", false),
            ("en5", "192.168.1.20", false),
            ("en0", "192.168.0.16", false),
            ("en0", "2001:db8::5", true)
        ]
        let list = NetworkInterfaces.build(from: records, types: types)
        #expect(list.map(\.name) == ["en0", "en5", "utun4"])
        #expect(list.map(\.kind) == [.wifi, .ethernet, .vpn])
        #expect(list[0].ipv6 == ["2001:db8::5"])
    }

    @Test func dropsSystemInterfacesAndLinkLocalOnly() {
        let records: [NetworkInterfaces.Record] = [
            ("lo0", "127.0.0.1", false),
            ("awdl0", "fe80::1", true),
            ("utun0", "fe80::2", true),
            ("bridge100", "192.168.64.1", false),
            ("en0", "192.168.0.16", false)
        ]
        let list = NetworkInterfaces.build(from: records, types: types)
        #expect(list.map(\.name) == ["en0"])
    }

    @Test func removesDuplicateAddresses() {
        let records: [NetworkInterfaces.Record] = [
            ("en0", "192.168.0.16", false),
            ("en0", "192.168.0.16", false)
        ]
        #expect(NetworkInterfaces.build(from: records, types: types)[0].ipv4 == ["192.168.0.16"])
    }

    @Test func classifiesUnknownAsOther() {
        #expect(NetworkInterfaces.classify(name: "en9", scType: nil) == .other)
        #expect(NetworkInterfaces.classify(name: "utun3", scType: nil) == .vpn)
    }
}
