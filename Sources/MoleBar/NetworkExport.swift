import Foundation

/// Ağ arayüzü bilgisini panoya ve CSV'ye uygun metne çevirir.
enum NetworkExport {
    static var header: [String] { [L("Arayüz"), L("Tür"), "IPv4", "IPv6", L("Ağ geçidi"), "DNS"] }

    static func rows(_ items: [NetworkInterface], external: ExternalIPInfo?) -> [[String]] {
        var rows = items.map { item in
            [item.name, item.kind.title, item.ipv4.joined(separator: " "), item.ipv6.joined(separator: " "),
             item.router ?? "", item.dns.joined(separator: " ")]
        }
        if let external {
            rows.append([L("Dış IP"), L("Dış"), external.address, external.ipv6 ?? "", "", ""])
        }
        return rows
    }

    static func csv(_ items: [NetworkInterface], external: ExternalIPInfo?) -> String {
        CSVExport.make(header: header, rows: rows(items, external: external))
    }

    /// Destek talebine yapıştırmaya uygun düz metin.
    static func text(_ items: [NetworkInterface], external: ExternalIPInfo?) -> String {
        var lines: [String] = []
        if let external {
            lines.append(L("Dış IP: %@", external.address) + (external.detailText.map { " (\($0))" } ?? ""))
            if let six = external.ipv6 { lines.append(L("Dış IPv6: %@", six)) }
        }
        for item in items {
            lines.append("\(item.kind.title) (\(item.name))")
            if !item.ipv4.isEmpty { lines.append("  IPv4: \(item.ipv4.joined(separator: ", "))") }
            if !item.ipv6.isEmpty { lines.append("  IPv6: \(item.ipv6.joined(separator: ", "))") }
            if let router = item.router { lines.append(L("  Ağ geçidi: %@", router)) }
            if !item.dns.isEmpty { lines.append("  DNS: \(item.dns.joined(separator: ", "))") }
        }
        return lines.joined(separator: "\n")
    }
}
