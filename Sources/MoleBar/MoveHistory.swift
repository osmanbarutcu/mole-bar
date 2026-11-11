import AppKit
import SwiftUI

@MainActor
final class MoveHistoryModel: ObservableObject {
    @Published private(set) var records: [MoveRecord] = []

    func reload() { records = MoveLog.load() }

    func clear() {
        MoveLog.clear()
        reload()
    }

    /// Geri alma sonucu. Başarıda kayıt listeden çıkar.
    @Published var notice: String?

    func restore(_ record: MoveRecord) {
        do {
            try MoveRestore.restore(record)
            MoveLog.remove(id: record.id)
            notice = L("%@ özgün yerine geri konuldu.", record.name)
        } catch let failure as MoveRestore.Failure {
            notice = failure.message
            ErrorLog.add(source: "Geri alma", message: "\(record.name): \(failure.message)")
        } catch {
            notice = L("%1$@ geri alınamadı: %2$@", record.name, error.localizedDescription)
            ErrorLog.add(source: "Geri alma", message: "\(record.name): \(error.localizedDescription)")
        }
        reload()
    }
}

/// Ayarlar sayfasında son 50 taşımayı listeler. Dosyaları silmez. "Temizle" yalnızca listeyi boşaltır.
struct MoveHistoryCard: View {
    @StateObject private var model = MoveHistoryModel()

    private static let dateFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "d MMM HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "clock.arrow.circlepath", title: "Son işlemler", trailing: model.records.isEmpty ? "" : L("%ld kayıt", model.records.count))
            if model.records.isEmpty {
                Text("Henüz Çöp Kutusu'na taşıma yok.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(model.records.prefix(8)) { record in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(record.name).font(.caption.weight(.medium)).lineLimit(1).truncationMode(.middle)
                            Text("\(L(record.source)) · \(Self.dateFormat.string(from: record.date))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 6)
                        Text(formatBytes(record.bytes)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Button("Geri al") { model.restore(record) }
                            .glassButton()
                            .controlSize(.small)
                            .help("Dosyayı özgün yerine geri koyar")
                        Button { reveal(record) } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Çöp Kutusu'nda göster")
                    }
                }
                if let notice = model.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                Button("Listeyi temizle") { model.clear() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text("Temizle yalnızca bu listeyi boşaltır. Çöp Kutusu'ndaki dosyalara dokunmaz.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .onAppear { model.reload() }
    }

    private func reveal(_ record: MoveRecord) {
        if let path = record.trashedPath, FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else {
            NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
        }
    }
}

@MainActor
final class ErrorHistoryModel: ObservableObject {
    @Published private(set) var records: [ErrorRecord] = []

    func reload() { records = ErrorLog.load() }

    func clear() {
        ErrorLog.clear()
        reload()
    }
}

/// Ayarlar sayfasında son hataları listeler. Hata yoksa kısa bir not gösterir.
struct ErrorHistoryCard: View {
    @StateObject private var model = ErrorHistoryModel()

    private static let dateFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "d MMM HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "exclamationmark.triangle", title: "Son hatalar", trailing: model.records.isEmpty ? "" : L("%ld kayıt", model.records.count))
            if model.records.isEmpty {
                Text("Kayıtlı hata yok.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(model.records.prefix(6)) { record in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(record.message).font(.caption).fixedSize(horizontal: false, vertical: true)
                        Text("\(L(record.source)) · \(Self.dateFormat.string(from: record.date))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Listeyi temizle") { model.clear() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .onAppear { model.reload() }
    }
}
