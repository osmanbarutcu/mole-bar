import SwiftUI

/// Panelde hızlı eylem. Önbelleği tarar ve Çöp Kutusu'nu boşaltır. Ayrıntılı seçim büyük pencerededir.
struct QuickCleanCard: View {
    @ObservedObject var cleaner: CacheCleaner
    let openCaches: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "bolt", title: "Hızlı eylem")
            HStack {
                Text("Çöp Kutusu").font(.subheadline)
                Spacer(minLength: 8)
                Text(cleaner.hasScanned ? formatBytes(cleaner.trashBytes) : "Taranmadı")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Önbellek").font(.subheadline)
                Spacer(minLength: 8)
                Text(cleaner.hasScanned ? formatBytes(cleaner.items.reduce(0) { $0 + $1.bytes }) : "Taranmadı")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if cleaner.confirmingEmpty {
                Text("Kalıcı silinir, geri alınamaz.").font(.caption).foregroundStyle(.red)
                HStack {
                    Button("Boşalt") { cleaner.emptyTrash() }.glassProminentButton()
                    Button("Vazgeç") { cleaner.confirmingEmpty = false }.glassButton()
                }
            } else {
                HStack {
                    Button { cleaner.scan() } label: {
                        if cleaner.isScanning { ProgressView().controlSize(.small) } else { Text("Tara") }
                    }
                    .glassButton()
                    .disabled(cleaner.isScanning)
                    Button("Çöp Kutusu'nu boşalt") { cleaner.confirmingEmpty = true }
                        .glassButton()
                        .disabled(!cleaner.hasScanned || cleaner.trashBytes == 0)
                    Spacer(minLength: 0)
                    Button("Aç", action: openCaches).glassButton()
                }
                .controlSize(.small)
            }
            if let notice = cleaner.notice {
                Text(notice).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
