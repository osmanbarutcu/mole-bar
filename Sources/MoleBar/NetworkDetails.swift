import Foundation
import SystemConfiguration

/// Bir arayüzün ağ geçidi ve DNS sunucuları.
struct NetworkRouting: Equatable {
    var router: String?
    var dns: [String]
}

/// Ağ geçidi ve DNS sunucularını `SystemConfiguration` dinamik deposundan okur. Dış servis çağrılmaz.
enum NetworkDetails {
    struct Entry: Equatable {
        let interface: String
        let router: String?
        let dns: [String]
    }

    /// Aynı arayüzün birden çok kaydını birleştirir. Boş değer ve kopya adres düşer.
    static func map(_ entries: [Entry]) -> [String: NetworkRouting] {
        var result: [String: NetworkRouting] = [:]
        for entry in entries where !entry.interface.isEmpty {
            var current = result[entry.interface] ?? NetworkRouting(router: nil, dns: [])
            if current.router == nil, let router = entry.router, !router.isEmpty { current.router = router }
            for server in entry.dns where !server.isEmpty && !current.dns.contains(server) {
                current.dns.append(server)
            }
            result[entry.interface] = current
        }
        return result
    }

    /// `State:/Network/Service/<kimlik>/IPv4` ve `/DNS` kayıtlarını okur. Okunamazsa boş döner.
    nonisolated static func read() -> [Entry] {
        guard let store = SCDynamicStoreCreate(nil, "MoleBar" as CFString, nil, nil),
              let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Service/[^/]+/IPv4" as CFString) as? [String]
        else { return [] }
        return keys.sorted().compactMap { key in
            guard let ipv4 = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
                  let interface = ipv4["InterfaceName"] as? String else { return nil }
            let dnsKey = key.replacingOccurrences(of: "/IPv4", with: "/DNS")
            let dnsValue = SCDynamicStoreCopyValue(store, dnsKey as CFString) as? [String: Any]
            return Entry(interface: interface,
                         router: ipv4["Router"] as? String,
                         dns: dnsValue?["ServerAddresses"] as? [String] ?? [])
        }
    }
}
