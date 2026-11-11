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
        case .other: L("Diğer")
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
    var router: String? = nil
    var dns: [String] = []
    var id: String { name }

    /// Ağ geçidi ve DNS bilgisi eklenmiş kopya. Özgün değer değişmez.
    func with(routing: NetworkRouting?) -> NetworkInterface {
        NetworkInterface(name: name, kind: kind, ipv4: ipv4, ipv6: ipv6,
                         router: routing?.router, dns: routing?.dns ?? [])
    }
}

/// Dış (genel) IP adresi sorgusunun durumu.
enum ExternalIPState: Equatable {
    case idle, loading
    case address(ExternalIPInfo)
    case failed
}

/// Dış IP ve (alınabildiyse) ülke ile servis sağlayıcı adı.
struct ExternalIPInfo: Equatable {
    let address: String
    var ipv6: String?
    var country: String?
    var isp: String?

    /// "Türkiye · Örnek Telekom" biçiminde. Bilgi yoksa nil.
    var detailText: String? {
        let parts = [country, isp].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// VPN arayüzü ile varsayılan rota arasındaki ilişki. Kesin kanıt değil, ipucudur.
enum VPNHint: Equatable {
    case routed      // Varsayılan rota VPN arayüzünden geçer.
    case notDefault  // VPN arayüzü açık, ama varsayılan rota başka arayüzden geçer.

    var text: String {
        switch self {
        case .routed: L("Varsayılan rota VPN arayüzünden geçiyor.")
        case .notDefault: L("VPN arayüzü açık, ama varsayılan rota VPN'den geçmiyor. Trafik VPN dışına çıkıyor olabilir (split tunnel).")
        }
    }

    /// VPN arayüzü yoksa nil döner. `primary`, varsayılan IPv4 rotasının arayüz adıdır.
    static func evaluate(primary: String?, interfaces: [NetworkInterface]) -> VPNHint? {
        guard interfaces.contains(where: { $0.kind == .vpn && !$0.ipv4.isEmpty }) else { return nil }
        guard let primary else { return nil }
        return NetworkInterfaces.classify(name: primary, scType: nil) == .vpn ? .routed : .notDefault
    }
}

/// Dış IP'yi `api.ipify.org` üzerinden okur. Yalnızca kullanıcı isteyince çağrılır.
enum ExternalIP {
    static let endpoint = URL(string: "https://api.ipify.org")!

    static let endpointV6 = URL(string: "https://api6.ipify.org")!

    /// Yanıt geçerli bir IPv4 veya IPv6 adresi değilse nil döner.
    static func parse(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        var v4 = in_addr()
        var v6 = in6_addr()
        let valid = inet_pton(AF_INET, text, &v4) == 1 || inet_pton(AF_INET6, text, &v6) == 1
        return valid ? text : nil
    }

    /// Yalnızca geçerli bir IPv6 adresi kabul eder.
    static func parseIPv6(_ data: Data) -> String? {
        guard let text = parse(data), text.contains(":") else { return nil }
        return text
    }

    /// Ülke ve servis sağlayıcı için ikinci servis. Adres yalnızca bu istekte yola eklenir.
    static func detailsURL(for address: String) -> URL? {
        URL(string: "https://ipwho.is/\(address)?fields=success,country,connection")
    }

    /// `ipwho.is` yanıtından ülke ve servis sağlayıcıyı okur. `success` false ise nil döner.
    static func parseDetails(_ data: Data) -> (country: String?, isp: String?)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["success"] as? Bool == true else { return nil }
        let isp = (json["connection"] as? [String: Any])?["isp"] as? String
        return (json["country"] as? String, isp)
    }

    private static func get(_ url: URL, timeout: TimeInterval = 10) async -> Data? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("MoleBar/\(UpdateCheck.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    /// Yalnızca adresi okur (`ipify`). Değişim izleyicisi bunu kullanır.
    static func fetchAddress() async -> String? {
        guard let data = await get(endpoint) else { return nil }
        return parse(data)
    }

    /// IPv6 yoksa servis hata verir. Bu durum normaldir. 4 sn sonra vazgeçilir.
    static func fetchIPv6() async -> String? {
        guard let data = await get(endpointV6, timeout: 4) else { return nil }
        return parseIPv6(data)
    }

    /// Adres alınamazsa nil döner. Ülke, servis sağlayıcı ve IPv6 alınamazsa yalnızca adres döner.
    static func fetch() async -> ExternalIPInfo? {
        async let ipv6 = fetchIPv6()
        guard let address = await fetchAddress() else { return nil }
        var info = ExternalIPInfo(address: address)
        if let url = detailsURL(for: address), let body = await get(url), let details = parseDetails(body) {
            info.country = details.country
            info.isp = details.isp
        }
        if let six = await ipv6, six != address { info.ipv6 = six }
        return info
    }
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

    /// Varsayılan IPv4 rotasının arayüz adı (`en0`, `utun4`...). Okunamazsa nil.
    nonisolated static func primaryInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "MoleBar" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return nil }
        return global["PrimaryInterface"] as? String
    }

    nonisolated static func scan() -> [NetworkInterface] {
        let routing = NetworkDetails.map(NetworkDetails.read())
        return build(from: readRecords(), types: systemTypes()).map { $0.with(routing: routing[$0.name]) }
    }
}

@MainActor
final class NetworkInterfaceModel: ObservableObject {
    @Published private(set) var items: [NetworkInterface] = []
    @Published private(set) var loaded = false
    @Published private(set) var external: ExternalIPState = .idle
    @Published private(set) var vpnHint: VPNHint?
    @Published private(set) var wifi: WifiInfo?
    private var externalTask: Task<Void, Never>?

    func fetchExternal() {
        guard external != .loading else { return }
        external = .loading
        externalTask = Task {
            let info = await ExternalIP.fetch()
            guard !Task.isCancelled else { return }
            external = info.map { .address($0) } ?? .failed
        }
    }

    /// Kart kapanınca bekleyen sorguyu iptal eder.
    func cancelExternal() {
        externalTask?.cancel()
        externalTask = nil
        if external == .loading { external = .idle }
    }

    func reload() {
        Task {
            let (list, primary, wifiInfo) = await Task.detached {
                (NetworkInterfaces.scan(), NetworkInterfaces.primaryInterface(), WifiDetails.read())
            }.value
            items = list
            wifi = wifiInfo
            vpnHint = VPNHint.evaluate(primary: primary, interfaces: list)
            loaded = true
        }
    }
}

/// Araçlar sayfasında Wi-Fi, Ethernet ve VPN arayüzlerinin IP adreslerini gösterir. Salt okunur.
struct NetworkInterfacesCard: View {
    @StateObject private var model = NetworkInterfaceModel()
    @AppStorage("externalIPAuto") private var autoExternal = false
    @AppStorage(ExternalIPChange.defaultsKey) private var watchExternal = false
    @StateObject private var location = LocationAccess()

    private var externalRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "globe").frame(width: 22).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Dış IP").font(.caption)
                switch model.external {
                case .idle:
                    Text("Sorgulanmadı.").font(.caption2).foregroundStyle(.secondary)
                case .loading:
                    Text("Sorgulanıyor...").font(.caption2).foregroundStyle(.secondary)
                case .failed:
                    Text("Alınamadı. Bağlantıyı kontrol edin.").font(.caption2).foregroundStyle(.secondary)
                case .address(let info):
                    Text(verbatim: info.address)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let six = info.ipv6 {
                        Text(verbatim: six)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let detail = info.detailText {
                        Text(verbatim: detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            Spacer(minLength: 6)
            if case .address(let info) = model.external {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(info.address, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                    .glassButton()
                    .controlSize(.small)
                    .help("Dış IP adresini kopyala")
                    .accessibilityLabel("Dış IP adresini kopyala")
            }
            Button { model.fetchExternal() } label: { Image(systemName: "arrow.clockwise") }
                .glassButton()
                .controlSize(.small)
                .disabled(model.external == .loading)
                .help("Dış IP adresini sorgula (api.ipify.org, ipwho.is)")
                .accessibilityLabel("Dış IP adresini sorgula")
        }
    }

    private func detailLine(_ title: String, _ value: String) -> some View {
        Text(verbatim: "\(L(title)): \(value)")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .lineLimit(2)
    }

    private var externalInfo: ExternalIPInfo? {
        if case .address(let info) = model.external { return info }
        return nil
    }

    private func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(NetworkExport.text(model.items, external: externalInfo), forType: .string)
    }

    private func exportCSV() {
        _ = CSVExport.save(NetworkExport.csv(model.items, external: externalInfo), suggestedName: "ag-bilgisi.csv")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardHeader(symbol: "network", title: "IP adresleri",
                           trailing: model.loaded ? L("%ld arayüz", model.items.count) : "")
                Button { copyAll() } label: { Image(systemName: "doc.on.clipboard") }
                    .glassButton()
                    .controlSize(.small)
                    .disabled(model.items.isEmpty)
                    .help("Tüm bilgiyi kopyala")
                    .accessibilityLabel("Tüm ağ bilgisini kopyala")
                Button { exportCSV() } label: { Image(systemName: "square.and.arrow.up") }
                    .glassButton()
                    .controlSize(.small)
                    .disabled(model.items.isEmpty)
                    .help("CSV olarak kaydet")
                    .accessibilityLabel("CSV olarak kaydet")
                Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .glassButton()
                    .controlSize(.small)
                    .help("Yenile")
                    .accessibilityLabel("Yenile")
            }
            externalRow
            Toggle("Kart açılınca dış IP'yi otomatik sorgula", isOn: $autoExternal)
                .font(.caption2)
                .toggleStyle(.switch)
                .controlSize(.mini)
            Toggle("Dış IP değişince bildir (5 dk'da bir sorgular)", isOn: $watchExternal)
                .font(.caption2)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .onChange(of: watchExternal) { _, value in ExternalIPWatcher.shared.apply(enabled: value) }
            if let hint = model.vpnHint {
                Label(hint.text, systemImage: hint == .routed ? "checkmark.shield" : "exclamationmark.shield")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.items.isEmpty {
                Text(model.loaded ? L("Adresi olan arayüz bulunamadı.") : L("Okunuyor...")).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(model.items) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.kind.symbol).frame(width: 22).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "\(item.kind.title) (\(item.name))").font(.caption)
                            ForEach(item.ipv4 + item.ipv6, id: \.self) { address in
                                Text(verbatim: address)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            if let router = item.router {
                                detailLine("Ağ geçidi", router)
                            }
                            if !item.dns.isEmpty {
                                detailLine("DNS", item.dns.joined(separator: ", "))
                            }
                            if item.kind == .wifi, let wifi = model.wifi {
                                detailLine("Wi-Fi", wifi.summary)
                                if wifi.ssid == nil && !location.granted {
                                    Button("SSID için konum izni ver") { location.request() }
                                        .buttonStyle(.link)
                                        .font(.caption2)
                                }
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
                            .accessibilityLabel(L("%@ adresini kopyala", item.name))
                    }
                }
            }
            Text("Yalnızca çalışan arayüzler listelenir. Bağlantı-yerel IPv6 ve sistem arayüzleri gizlenir. Yerel adresler bu Mac'ten çıkmaz. Dış IP, sorgu düğmesine basınca (veya otomatik seçenekler açıksa) api.ipify.org ve api6.ipify.org'dan okunur. Ülke ve servis sağlayıcı için IP adresi ipwho.is'e de gönderilir.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .onAppear {
            if !model.loaded { model.reload() }
            if autoExternal, model.external == .idle { model.fetchExternal() }
        }
        .onDisappear { model.cancelExternal() }
    }
}
