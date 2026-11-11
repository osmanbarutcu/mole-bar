import Foundation

/// Dış IP değişiminde bildirim üretir. Yalnızca kullanıcı açarsa çalışır.
enum ExternalIPChange {
    /// Sorgular arası en kısa süre (sn). Servise gereksiz yük bindirmez.
    static let interval: TimeInterval = 300
    static let defaultsKey = "externalIPWatch"

    /// İlk okuma taban değerdir, bildirim üretmez. Adres aynıysa da nil döner.
    static func message(previous: String?, current: String) -> (title: String, body: String)? {
        guard let previous, previous != current else { return nil }
        return (L("Dış IP değişti"), L("%@ → %@. VPN bağlantısı düşmüş veya ağ değişmiş olabilir.", previous, current))
    }
}

@MainActor
final class ExternalIPWatcher {
    static let shared = ExternalIPWatcher()

    private var task: Task<Void, Never>?
    private var last: String?

    var isRunning: Bool { task != nil }

    /// Açar veya kapatır. Kapatınca bekleyen sorgu iptal olur ve taban değer silinir.
    func apply(enabled: Bool) {
        guard enabled else {
            task?.cancel()
            task = nil
            last = nil
            return
        }
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: .seconds(ExternalIPChange.interval))
            }
        }
    }

    private func check() async {
        guard let address = await ExternalIP.fetchAddress(), !Task.isCancelled else { return }
        if let message = ExternalIPChange.message(previous: last, current: address) {
            DiskNotifier.post(title: message.title, body: message.body, id: "molebar.externalip")
        }
        last = address
    }
}
