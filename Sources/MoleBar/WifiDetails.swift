import AppKit
import CoreLocation
import CoreWLAN

/// Bağlı Wi-Fi ağının SSID, kanal ve sinyal bilgisi.
struct WifiInfo: Equatable {
    let ssid: String?
    let rssi: Int
    let channel: Int?
    let band: String?
    let rate: Double

    var quality: String { WifiDetails.quality(rssi: rssi) }

    /// "Ev · Kanal 36 (5 GHz) · -55 dBm (İyi) · 866 Mb/sn". SSID yoksa başa yazılmaz.
    var summary: String {
        var parts: [String] = []
        if let ssid, !ssid.isEmpty { parts.append(ssid) }
        if let channel { parts.append("Kanal \(channel)" + (band.map { " (\($0))" } ?? "")) }
        parts.append("\(rssi) dBm (\(quality))")
        if rate > 0 { parts.append("\(Int(rate.rounded())) Mb/sn") }
        return parts.joined(separator: " · ")
    }
}

/// Wi-Fi bilgisini `CoreWLAN` ile okur. Dış servis çağrılmaz.
enum WifiDetails {
    /// Sinyal gücünü (dBm) dört kademeye çevirir.
    static func quality(rssi: Int) -> String {
        switch rssi {
        case (-50)...: "Mükemmel"
        case (-60)...: "İyi"
        case (-70)...: "Orta"
        default: "Zayıf"
        }
    }

    static func bandLabel(_ band: CWChannelBand) -> String? {
        switch band {
        case .band2GHz: "2,4 GHz"
        case .band5GHz: "5 GHz"
        case .band6GHz: "6 GHz"
        default: nil
        }
    }

    /// Wi-Fi kapalıysa veya bağlı değilse (RSSI 0) nil döner. SSID, konum izni yoksa nil olur.
    nonisolated static func read() -> WifiInfo? {
        guard let interface = CWWiFiClient.shared().interface(), interface.powerOn() else { return nil }
        let rssi = interface.rssiValue()
        guard rssi != 0 else { return nil }
        let channel = interface.wlanChannel()
        return WifiInfo(ssid: interface.ssid(), rssi: rssi,
                        channel: channel?.channelNumber,
                        band: channel.flatMap { bandLabel($0.channelBand) },
                        rate: interface.transmitRate())
    }
}

/// SSID okumak macOS'ta Konum izni ister. Konum verisi okunmaz, yalnızca izin durumu kullanılır.
@MainActor
final class LocationAccess: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var granted = false
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        granted = manager.authorizationStatus == .authorizedAlways
    }

    /// Paketsiz (SwiftPM) çalışmada izin istenmez. `Info.plist` gerekir.
    func request() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in granted = status == .authorizedAlways }
    }
}
