import SwiftUI

/// Ana diskin günlük kullanım ölçümü.
struct DiskSample: Codable, Identifiable {
    let day: String
    var usedBytes: UInt64
    var totalBytes: UInt64
    var id: String { day }
}

/// Günde bir ölçüm tutar. Aynı gün yeni ölçüm eskisini değiştirir. En çok 90 gün saklanır.
enum DiskLog {
    private static let key = "diskLog"
    private static let limit = 90

    private static let dayFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func date(of sample: DiskSample) -> Date? { dayFormat.date(from: sample.day) }
    static func date(day: String) -> Date? { dayFormat.date(from: day) }
    static func dayString(_ date: Date) -> String { dayFormat.string(from: date) }

    static func load() -> [DiskSample] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([DiskSample].self, from: data)) ?? []
    }

    static func record(_ snapshot: DiskSnapshot, now: Date = Date()) {
        guard snapshot.totalBytes > 0 else { return }
        let today = dayFormat.string(from: now)
        var all = load()
        let sample = DiskSample(day: today, usedBytes: snapshot.usedBytes, totalBytes: snapshot.totalBytes)
        if let last = all.last, last.day == today { all[all.count - 1] = sample } else { all.append(sample) }
        if all.count > limit { all.removeFirst(all.count - limit) }
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: key) }
    }
}

@MainActor
final class DiskGrowthModel: ObservableObject {
    @Published private(set) var samples: [DiskSample] = []
    @Published private(set) var growing: [FolderGrowthEntry] = []

    func reload() {
        samples = Array(DiskLog.load().suffix(30))
        growing = Array(FolderGrowth.compute(Array(FolderLog.load().suffix(30))).prefix(5))
    }

    /// Son 7 günlük değişim. Ölçüm penceresi 7 günden kısaysa eldeki en eski ölçümle karşılaştırılır.
    var weekDelta: (bytes: Int64, days: Int)? {
        guard let last = samples.last, let lastDate = DiskLog.date(of: last) else { return nil }
        let cutoff = lastDate.addingTimeInterval(-7 * 86_400)
        guard let base = samples.first(where: { (DiskLog.date(of: $0) ?? .distantFuture) >= cutoff }),
              base.id != last.id, let baseDate = DiskLog.date(of: base) else { return nil }
        let days = Calendar.current.dateComponents([.day], from: baseDate, to: lastDate).day ?? 0
        return (Int64(last.usedBytes) - Int64(base.usedBytes), days)
    }
}

/// Diskler sayfasında kullanılan alanın son 30 gündeki seyrini gösterir.
struct DiskGrowthCard: View {
    @StateObject private var model = DiskGrowthModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "chart.line.uptrend.xyaxis", title: "Disk büyümesi", trailing: "son 30 gün")
            if let delta = model.weekDelta {
                let sign = delta.bytes >= 0 ? "+" : "-"
                Text(L("Son %ld günde %@%@ kullanım", delta.days, sign, formatBytes(UInt64(abs(delta.bytes)))))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(delta.bytes > 0 ? Color.orange : Color.green)
                trend
                growingList
            } else {
                Text("Ölçüm birikiyor. MoleBar günde bir kez kullanılan alanı kaydeder. En az iki gün gerekir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .onAppear { model.reload() }
    }

    /// Önbellek sayfası taranınca kaydedilen klasörlerin büyümesi. Veri yoksa hiçbir şey göstermez.
    @ViewBuilder
    private var growingList: some View {
        if !model.growing.isEmpty {
            Divider().opacity(0.4)
            Text("En çok büyüyenler").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(model.growing) { entry in
                HStack {
                    Text(L(entry.name)).font(.caption)
                    Spacer(minLength: 8)
                    Text(L("+%@ · %ld gün", formatBytes(entry.bytes), entry.days))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Text("Yalnızca Önbellek sayfasında taranan öğeler izlenir. Ev klasörünün tamamı taranmaz.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var trend: some View {
        let values = model.samples.map { Double($0.usedBytes) }
        return GeometryReader { proxy in
            let low = values.min() ?? 0
            let span = max((values.max() ?? 0) - low, 1)
            Path { path in
                guard values.count > 1 else { return }
                let step = proxy.size.width / CGFloat(values.count - 1)
                for (index, value) in values.enumerated() {
                    let y = proxy.size.height * (1 - CGFloat((value - low) / span))
                    let point = CGPoint(x: CGFloat(index) * step, y: y)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 44)
    }
}
