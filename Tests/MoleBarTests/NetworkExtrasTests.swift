import Foundation
import Testing
@testable import MoleBar

struct NetworkExtrasTests {
    // MARK: Ağ geçidi ve DNS

    @Test func mergesRoutingPerInterface() {
        let entries = [
            NetworkDetails.Entry(interface: "en0", router: "192.168.0.1", dns: ["1.1.1.1", "8.8.8.8"]),
            NetworkDetails.Entry(interface: "en0", router: "10.0.0.1", dns: ["1.1.1.1", "9.9.9.9"]),
            NetworkDetails.Entry(interface: "utun4", router: nil, dns: []),
            NetworkDetails.Entry(interface: "", router: "1.2.3.4", dns: ["4.4.4.4"])
        ]
        let map = NetworkDetails.map(entries)
        #expect(map["en0"] == NetworkRouting(router: "192.168.0.1", dns: ["1.1.1.1", "8.8.8.8", "9.9.9.9"]))
        #expect(map["utun4"] == NetworkRouting(router: nil, dns: []))
        #expect(map.count == 2)
    }

    @Test func attachesRoutingWithoutChangingOriginal() {
        let base = NetworkInterface(name: "en0", kind: .wifi, ipv4: ["192.168.0.16"], ipv6: [])
        let merged = base.with(routing: NetworkRouting(router: "192.168.0.1", dns: ["1.1.1.1"]))
        #expect(merged.router == "192.168.0.1")
        #expect(merged.dns == ["1.1.1.1"])
        #expect(base.router == nil)
    }

    // MARK: Dışa aktarma

    @Test func exportsTextAndCsv() {
        let items = [NetworkInterface(name: "en0", kind: .wifi, ipv4: ["192.168.0.16"], ipv6: ["2001:db8::5"],
                                      router: "192.168.0.1", dns: ["1.1.1.1"])]
        var external = ExternalIPInfo(address: "203.0.113.7")
        external.ipv6 = "2001:db8::7"
        external.country = "Türkiye"
        let text = NetworkExport.text(items, external: external)
        #expect(text.hasPrefix("Dış IP: 203.0.113.7 (Türkiye)\nDış IPv6: 2001:db8::7\nWi-Fi (en0)"))
        #expect(text.contains("  Ağ geçidi: 192.168.0.1"))
        let csv = NetworkExport.csv(items, external: external)
        #expect(csv.hasPrefix("Arayüz,Tür,IPv4,IPv6,Ağ geçidi,DNS\n"))
        #expect(csv.contains("Dış IP,Dış,203.0.113.7,2001:db8::7,,"))
    }

    // MARK: Wi-Fi

    @Test func ratesWifiSignal() {
        #expect(WifiDetails.quality(rssi: -45) == "Mükemmel")
        #expect(WifiDetails.quality(rssi: -55) == "İyi")
        #expect(WifiDetails.quality(rssi: -65) == "Orta")
        #expect(WifiDetails.quality(rssi: -80) == "Zayıf")
    }

    @Test func summarizesWifi() {
        let info = WifiInfo(ssid: "Ev", rssi: -55, channel: 36, band: "5 GHz", rate: 866)
        #expect(info.summary == "Ev · Kanal 36 (5 GHz) · -55 dBm (İyi) · 866 Mb/sn")
        let hidden = WifiInfo(ssid: nil, rssi: -70, channel: nil, band: nil, rate: 0)
        #expect(hidden.summary == "-70 dBm (Orta)")
    }

    // MARK: Dış IP

    @Test func parsesOnlyIPv6() {
        #expect(ExternalIP.parseIPv6(Data("2001:db8::1\n".utf8)) == "2001:db8::1")
        #expect(ExternalIP.parseIPv6(Data("203.0.113.7".utf8)) == nil)
    }

    @Test func reportsExternalIPChangeOnlyOnChange() {
        #expect(ExternalIPChange.message(previous: nil, current: "1.1.1.1") == nil)
        #expect(ExternalIPChange.message(previous: "1.1.1.1", current: "1.1.1.1") == nil)
        let change = ExternalIPChange.message(previous: "1.1.1.1", current: "2.2.2.2")
        #expect(change?.title == "Dış IP değişti")
        #expect(change?.body.contains("1.1.1.1 → 2.2.2.2") == true)
    }

    // MARK: Hız ölçümü

    @Test func parsesSpeedResult() {
        let json = #"{"dl_throughput":187186384,"ul_throughput":25915314,"responsiveness":330.86,"base_rtt":65.28}"#
        let result = NetworkSpeed.parse(Data(json.utf8))
        #expect(result?.downloadMbps == 187.186384)
        #expect(result?.responsiveness == 331)
        #expect(result?.responsivenessLabel == "Orta")
        #expect(NetworkSpeed.parse(Data(#"{"dl_throughput":1}"#.utf8)) == nil)
        #expect(NetworkSpeed.parse(Data("x".utf8)) == nil)
    }

    // MARK: DNS sorgusu

    @Test func validatesHostnames() {
        #expect(DNSLookup.isValidHostname("azure.sosmartteknoloji.com"))
        #expect(DNSLookup.isValidHostname("example.com."))
        #expect(DNSLookup.isValidHostname("_dmarc.example.com"))
        #expect(!DNSLookup.isValidHostname(""))
        #expect(!DNSLookup.isValidHostname("-flush"))
        #expect(!DNSLookup.isValidHostname("a b.com"))
        #expect(!DNSLookup.isValidHostname("a..com"))
        #expect(!DNSLookup.isValidHostname("a;rm -rf.com"))
        #expect(!DNSLookup.isValidHostname("örnek.com"))
        #expect(!DNSLookup.isValidHostname(String(repeating: "a", count: 64) + ".com"))
    }

    @Test func parsesDscacheutilOutput() {
        let output = """
        name: azure.sosmartteknoloji.com
        ipv6_address: 2606:4700:3035::ac43:90e9
        ipv6_address: 2606:4700:3036::6815:a4b

        name: azure.sosmartteknoloji.com
        ip_address: 104.21.10.75
        ip_address: 172.67.144.233
        ip_address: 104.21.10.75

        """
        let result = DNSLookup.parse(output, fallbackName: "x")
        #expect(result.name == "azure.sosmartteknoloji.com")
        #expect(result.ipv4 == ["104.21.10.75", "172.67.144.233"])
        #expect(result.ipv6.count == 2)
        #expect(DNSLookup.parse("", fallbackName: "yok.invalid").isEmpty)
    }

    // MARK: Yönetici komutları

    @Test func buildsAdminScript() {
        #expect(AdminCommand.script(for: "/usr/sbin/purge") == #"do shell script "/usr/sbin/purge" with administrator privileges"#)
        #expect(AdminCommand.script(for: #"a"b\c"#).contains(#"a\"b\\c"#))
    }

    @Test func classifiesAdminOutcome() {
        #expect(AdminCommand.classify(status: 0, stderr: "") == .success)
        #expect(AdminCommand.classify(status: 1, stderr: "execution error: User canceled. (-128)") == .cancelled)
        #expect(AdminCommand.classify(status: 1, stderr: "x\nexecution error: boom (1)\n") == .failed("execution error: boom (1)"))
    }

    @Test func maintenanceCommandsAreFixedAndSafe() {
        for action in MaintenanceAction.allCases {
            #expect(action.command.hasPrefix("/usr/"))
            #expect(!action.command.contains("\""))
            #expect(!action.command.contains("\\"))
            #expect(!action.command.lowercased().contains("sudo"))
        }
    }
}
