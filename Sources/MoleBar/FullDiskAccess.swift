import AppKit
import SwiftUI

/// Tam Disk Erişimi durumu. Korumalı bir klasörü listelemeyi dener. Salt okunurdur.
enum FullDiskAccess {
    enum Status { case granted, denied, unknown }

    private static let probes = ["Library/Mail", "Library/Safari", "Library/Messages", ".Trash"]

    /// İlk var olan korumalı klasör listelenebiliyorsa izin verilmiştir. Hiçbiri yoksa durum bilinmez.
    static func status(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Status {
        for relative in probes {
            let url = home.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            return (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil ? .granted : .denied
        }
        return .unknown
    }

    /// Erişilemeyen öğe notu. İzin verilmişse sistem korumalı öğeler olduğunu söyler, izin istemez.
    static func inaccessibleNote(_ count: Int) -> String {
        status() == .granted
            ? "\(count) öğe okunamadı (sistem korumalı). Sonuçlar bu öğeler dışında eksiksizdir."
            : "\(count) öğeye erişilemedi (izin yok). Sonuçlar eksik. Sistem Ayarları > Gizlilik > Tam Disk Erişimi altında MoleBar'a izin verin."
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

@MainActor
final class FullDiskAccessModel: ObservableObject {
    @Published var status = FullDiskAccess.status()
    func recheck() { status = FullDiskAccess.status() }
}

struct FullDiskAccessCard: View {
    @StateObject private var model = FullDiskAccessModel()
    private var status: FullDiskAccess.Status { model.status }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "lock.open", title: "Tam Disk Erişimi", trailing: label)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Sistem Ayarları'nı aç") { FullDiskAccess.openSettings() }.glassButton().controlSize(.small)
                Button("Yeniden denetle") { model.recheck() }.glassButton().controlSize(.small)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var label: String {
        switch status {
        case .granted: return "Verildi"
        case .denied: return "Verilmedi"
        case .unknown: return "Bilinmiyor"
        }
    }

    private var detail: String {
        switch status {
        case .granted: return "Mail, Çöp Kutusu ve korumalı klasörler okunabilir. Tarama sonuçları eksiksizdir."
        case .denied: return "Mail boyutu, Çöp Kutusu ve bazı klasörler okunamaz. Listede MoleBar'ı kaldırıp yeniden ekleyin, sonra uygulamayı kapatıp açın."
        case .unknown: return "Denetlenecek korumalı klasör bulunamadı."
        }
    }
}
