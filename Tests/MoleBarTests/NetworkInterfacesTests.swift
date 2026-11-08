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

    @Test func parsesExternalIPv4AndIPv6() {
        #expect(ExternalIP.parse(Data("203.0.113.7\n".utf8)) == "203.0.113.7")
        #expect(ExternalIP.parse(Data("2001:db8::1".utf8)) == "2001:db8::1")
    }

    @Test func rejectsInvalidExternalResponse() {
        #expect(ExternalIP.parse(Data("<html>error</html>".utf8)) == nil)
        #expect(ExternalIP.parse(Data("999.1.1.1".utf8)) == nil)
        #expect(ExternalIP.parse(Data()) == nil)
    }

    @Test func parsesExternalDetails() {
        let body = Data(#"{"success":true,"country":"Türkiye","connection":{"isp":"Örnek Telekom"}}"#.utf8)
        let details = ExternalIP.parseDetails(body)
        #expect(details?.country == "Türkiye")
        #expect(details?.isp == "Örnek Telekom")
        #expect(ExternalIP.parseDetails(Data(#"{"success":false}"#.utf8)) == nil)
        #expect(ExternalIP.parseDetails(Data("x".utf8)) == nil)
    }

    @Test func buildsDetailText() {
        #expect(ExternalIPInfo(address: "1.1.1.1", country: "A", isp: "B").detailText == "A · B")
        #expect(ExternalIPInfo(address: "1.1.1.1", country: nil, isp: "B").detailText == "B")
        #expect(ExternalIPInfo(address: "1.1.1.1").detailText == nil)
    }

    @Test func evaluatesVpnHint() {
        let wifi = NetworkInterface(name: "en0", kind: .wifi, ipv4: ["192.168.0.16"], ipv6: [])
        let vpn = NetworkInterface(name: "utun4", kind: .vpn, ipv4: ["10.8.0.2"], ipv6: [])
        #expect(VPNHint.evaluate(primary: "utun4", interfaces: [wifi, vpn]) == .routed)
        #expect(VPNHint.evaluate(primary: "en0", interfaces: [wifi, vpn]) == .notDefault)
        #expect(VPNHint.evaluate(primary: "en0", interfaces: [wifi]) == nil)
        #expect(VPNHint.evaluate(primary: nil, interfaces: [wifi, vpn]) == nil)
    }
}
