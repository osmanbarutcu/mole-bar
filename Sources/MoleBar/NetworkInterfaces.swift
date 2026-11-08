import SwiftUI
import SystemConfiguration
import Darwin

/// Bir ağ arayüzünün türü.
enum InterfaceKind: String, Equatable {
    case wifi, ethernet, vpn, other

    var title: String {
        switch self {
        case .wifi: "Wi-Fi"
        case .ethernet: "Ethernet"
        case .vpn: "VPN"
        case .other: "Diğer"
        }
    }

    var symbol: String {
        switch self {
        case .wifi: "wifi"
        case .ethernet: "cable.connector.horizontal"
        case .vpn: "lock.shield"
        case .other: "network"
        }
    }

    /// Listede önce Wi-Fi, sonra Ethernet, sonra VPN gelir.
    var order: Int {
        switch self {
        case .wifi: 0
        case .ethernet: 1
        case .vpn: 2
        case .other: 3
        }
    }
}

/// Adresi olan, çalışan bir ağ arayüzü.
struct NetworkInterface: Identifiable, Equatable {
    let name: String
    let kind: InterfaceKind
    let ipv4: [String]
    let ipv6: [String]
    var id: String { name }
}

/// Yerel arayüzlerin IP adreslerini `getifaddrs` ile okur. Dış servis çağrılmaz.
enum NetworkInterfaces {
    typealias Record = (name: String, address: String, isV6: Bool)

    /// Kullanıcıya gösterilmeyen sistem arayüzleri.
    private static let hiddenPrefixes = ["lo", "awdl", "llw", "bridge", "anpi", "ap", "gif", "stf", "XHC", "pktap"]

    static func isHidden(_ name: String) -> Bool {
        hiddenPrefixes.contains { name.hasPrefix($0) }
    }

    /// `SystemConfiguration` türünden (varsa) arayüz türünü çıkarır. Tür yoksa addan tahmin eder.
    static func classify(name: String, scType: String?) -> InterfaceKind {
        if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") { return .vpn }
        guard let scType else { return .other }
        if scType == kSCNetworkInterfaceTypeIEEE80211 as String { return .wifi }
        if scType == kSCNetworkInterfaceTypeEthernet as String { return .ethernet }
        let vpnTypes = [kSCNetworkInterfaceTypePPP, kSCNetworkInterfaceTypeL2TP, kSCNetworkInterfaceTypeIPSec].map { $0 as String }
        return vpnTypes.contains(scType) ? .vpn : .other
    }

    /// Bağlantı-yerel IPv6 (`fe80::`) kullanıcı için anlamlı değildir. Listeden çıkar.
    static func isLinkLocalV6(_ address: String) -> Bool {
        address.lowercased().hasPrefix("fe80:")
    }

    /// Ham `(arayüz, adres)` çiftlerini kullanıcıya gösterilecek listeye çevirir.
    /// Adresi olmayan, gizli veya yalnızca bağlantı-yerel adresi olan arayüz düşer.
    static func build(from records: [Record], types: [String: String]) -> [NetworkInterface] {
        var v4: [String: [String]] = [:]
        var v6: [String: [String]] = [:]
        for record in records where !isHidden(record.name) {
            if record.isV6 {
                guard !isLinkLocalV6(record.address) else { continue }
                if !(v6[record.name] ?? []).contains(record.address) { v6[record.name, default: []].append(record.address) }
            } else if !(v4[record.name] ?? []).contains(record.address) {
                v4[record.name, default: []].append(record.address)
            }
        }
        let names = Set(v4.keys).union(v6.keys)
        return names.map { name in
            NetworkInterface(name: name, kind: classify(name: name, scType: types[name]),
                             ipv4: v4[name] ?? [], ipv6: v6[name] ?? [])
        }
        .sorted { $0.kind.order == $1.kind.order ? $0.name < $1.name : $0.kind.order < $1.kind.order }
    }

    /// `en0` gibi BSD adından SystemConfiguration arayüz türüne eşleme.
    nonisolated static func systemTypes() -> [String: String] {
        guard let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [:] }
        var map: [String: String] = [:]
        for item in all {
            if let bsd = SCNetworkInterfaceGetBSDName(item) as String?,
               let type = SCNetworkInterfaceGetInterfaceType(item) as String? {
                map[bsd] = type
            }
        }
        return map
    }

    /// Çalışan (`IFF_UP`) arayüzlerin IPv4 ve IPv6 adreslerini okur.
    nonisolated static func readRecords() -> [Record] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var records: [Record] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, let sockaddr = entry.pointee.ifa_addr else { continue }
            let family = Int32(sockaddr.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(sockaddr.pointee.sa_len)
            guard getnameinfo(sockaddr, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            var address = String(cString: host)
            // Kapsam eki (`%en0`) adresin parçası değildir.
            if let percent = address.firstIndex(of: "%") { address = String(address[..<percent]) }
            records.append((String(cString: entry.pointee.ifa_name), address, family == AF_INET6))
        }
        return records
    }

    nonisolated static func scan() -> [NetworkInterface] {
        build(from: readRecords(), types: systemTypes())
    }
}

@MainActor
final class NetworkInterfaceModel: ObservableObject {
    @Published private(set) var items: [NetworkInterface] = []
    @Published private(set) var loaded = false

    func reload() {
        Task {
            items = await Task.detached { NetworkInterfaces.scan() }.value
            loaded = true
        }
    }
}

/// Araçlar sayfasında Wi-Fi, Ethernet ve VPN arayüzlerinin IP adreslerini gösterir. Salt okunur.
struct NetworkInterfacesCard: View {
    @StateObject private var model = NetworkInterfaceModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardHeader(symbol: "network", title: "IP adresleri",
                           trailing: model.loaded ? "\(model.items.count) arayüz" : "")
                Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .glassButton()
                    .controlSize(.small)
                    .help("Yenile")
                    .accessibilityLabel("Yenile")
            }
            if model.items.isEmpty {
                Text(model.loaded ? "Adresi olan arayüz bulunamadı." : "Okunuyor...").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(model.items) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.kind.symbol).frame(width: 22).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(item.kind.title) (\(item.name))").font(.caption)
                            ForEach(item.ipv4 + item.ipv6, id: \.self) { address in
                                Text(verbatim: address)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        Spacer(minLength: 6)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString((item.ipv4 + item.ipv6).first ?? "", forType: .string)
                        } label: { Image(systemName: "doc.on.doc") }
                            .glassButton()
                            .controlSize(.small)
                            .help("İlk adresi kopyala")
                            .accessibilityLabel("\(item.name) adresini kopyala")
                    }
                }
            }
            Text("Yalnızca çalışan arayüzler listelenir. Bağlantı-yerel IPv6 ve sistem arayüzleri gizlenir. Adresler bu Mac'ten çıkmaz.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .onAppear { if !model.loaded { model.reload() } }
    }
}
