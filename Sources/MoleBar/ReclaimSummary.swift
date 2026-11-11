import SwiftUI

/// Her tarama sayfası son sonucunu buraya yazar. Kart bu değerleri okur.
/// Değer -1 ise sayfa henüz taranmamıştır.
enum ReclaimStore {
    enum Key: String, CaseIterable {
        case cache = "reclaim.cache"
        case trash = "reclaim.trash"
        case large = "reclaim.large"
        case duplicates = "reclaim.dups"
        case projects = "reclaim.projects"
    }

    static func save(_ key: Key, bytes: UInt64) {
        UserDefaults.standard.set(Int(clamping: bytes), forKey: key.rawValue)
    }
}

/// Diskler sayfasında kazanılabilir alanı kategori bazında gösterir.
/// Kategoriler çakışabilir (aynı dosya hem büyük hem kopya olabilir). Bu yüzden toplam gösterilmez.
struct ReclaimCard: View {
    let open: (MainSection) -> Void

    @AppStorage("reclaim.cache") private var cache = -1
    @AppStorage("reclaim.trash") private var trash = -1
    @AppStorage("reclaim.large") private var large = -1
    @AppStorage("reclaim.dups") private var dups = -1
    @AppStorage("reclaim.projects") private var projects = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "arrow.down.circle", title: "Kazanılabilir alan")
            row("archivebox", "Önbellek", cache, .caches)
            row("trash", "Çöp Kutusu", trash, .caches)
            row("doc.text.magnifyingglass", "Büyük dosyalar", large, .large)
            row("square.on.square", "Yinelenen kopyalar", dups, .duplicates)
            row("hammer", "Proje çıktıları", projects, .projects)
            Text("Kategoriler çakışabilir, bu yüzden toplam gösterilmez. Değerler son taramadan gelir.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func row(_ symbol: String, _ title: String, _ bytes: Int, _ section: MainSection) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 20).foregroundStyle(.secondary)
            Text(L(title)).font(.subheadline)
            Spacer(minLength: 8)
            Text(bytes < 0 ? L("Taranmadı") : formatBytes(UInt64(bytes)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(bytes < 0 ? .tertiary : .secondary)
            Button("Aç") { open(section) }
                .glassButton()
                .controlSize(.small)
        }
    }
}
