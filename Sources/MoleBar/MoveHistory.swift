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
}

/// Ayarlar sayfasında son 50 taşımayı listeler. Dosyaları silmez. "Temizle" yalnızca listeyi boşaltır.
struct MoveHistoryCard: View {
    @StateObject private var model = MoveHistoryModel()

    private static let dateFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMM HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(symbol: "clock.arrow.circlepath", title: "Son işlemler", trailing: model.records.isEmpty ? "" : "\(model.records.count) kayıt")
            if model.records.isEmpty {
                Text("Henüz Çöp Kutusu'na taşıma yok.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(model.records.prefix(8)) { record in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(record.name).font(.caption.weight(.medium)).lineLimit(1).truncationMode(.middle)
                            Text("\(record.source) · \(Self.dateFormat.string(from: record.date))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 6)
                        Text(formatBytes(record.bytes)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Button { reveal(record) } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Çöp Kutusu'nda göster")
                    }
                }
                Button("Listeyi temizle") { model.clear() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text("Temizle yalnızca bu listeyi boşaltır. Çöp Kutusu'ndaki dosyalara dokunmaz.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
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
