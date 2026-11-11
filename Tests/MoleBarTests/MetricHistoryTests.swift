import Foundation
import Testing
@testable import MoleBar

private func sample(_ seconds: TimeInterval, cpu: Double = 10, memory: Double = 50, disk: Double = 60,
                    topCPU: String? = nil, topMemory: String? = nil) -> MetricSample {
    MetricSample(time: Date(timeIntervalSince1970: seconds), cpu: cpu, memory: memory, disk: disk,
                 topCPU: topCPU, topMemory: topMemory)
}

@Suite("MetricHistory saf işlevler")
struct MetricHistoryTests {
    @Test("satır kodlanır ve geri okunur")
    func roundTrip() {
        let original = sample(1_000, cpu: 12.5, memory: 70.25, disk: 81, topCPU: "Xcode", topMemory: "Chrome")
        let line = MetricHistory.encode(original)
        #expect(line?.contains("\n") == false)
        let decoded = MetricHistory.decode(line.map { $0 + "\n" } ?? "")
        #expect(decoded.count == 1)
        #expect(decoded.first?.time == original.time)
        #expect(decoded.first?.cpu == 12.5)
        #expect(decoded.first?.topMemory == "Chrome")
    }

    @Test("bozuk ve boş satırlar atlanır")
    func skipsBadLines() {
        let good = MetricHistory.encode(sample(5)) ?? ""
        let text = "bozuk\n\n{\"t\":1}\n" + good + "\n" + "{yarım"
        #expect(MetricHistory.decode(text).count == 1)
    }

    @Test("pencere dışındaki eski örnekler atılır")
    func prune() {
        let now = Date(timeIntervalSince1970: 10_000)
        let samples = [sample(1_000), sample(9_000), sample(9_999)]
        let kept = MetricHistory.prune(samples, now: now, maxAge: 2_000)
        #expect(kept.map(\.time.timeIntervalSince1970) == [9_000, 9_999])
    }

    @Test("pencere yalnızca son süreyi verir")
    func window() {
        let samples = [sample(0), sample(3_000), sample(3_500), sample(3_600)]
        let last = MetricHistory.window(samples, duration: 700)
        #expect(last.map(\.time.timeIntervalSince1970) == [3_000, 3_500, 3_600])
        #expect(MetricHistory.window([], duration: 10).isEmpty)
    }

    @Test("seyreltme ortalama alır ve nokta sınırını aşmaz")
    func downsample() {
        let samples = (0..<10).map { sample(Double($0), cpu: Double($0), memory: 100 - Double($0)) }
        let reduced = MetricHistory.downsample(samples, maxPoints: 5)
        #expect(reduced.count == 5)
        #expect(reduced[0].cpu == 0.5)
        #expect(reduced[4].cpu == 8.5)
        #expect(reduced[0].memory == 99.5)
        // Sınırın altındaki liste aynen döner.
        #expect(MetricHistory.downsample(Array(samples.prefix(3)), maxPoints: 5).count == 3)
        #expect(MetricHistory.downsample(samples, maxPoints: 0).isEmpty)
    }

    @Test("zirve en yüksek değeri ve o andaki süreci verir")
    func peak() {
        let samples = [
            sample(1, memory: 40, topMemory: "Safari"),
            sample(2, memory: 92, topMemory: "Chrome"),
            sample(3, memory: 60, topMemory: "Mail")
        ]
        let top = MetricHistory.peak(samples, \.memory)
        #expect(top?.value == 92)
        #expect(top?.sample.topMemory == "Chrome")
        #expect(MetricHistory.peak([], \.cpu) == nil)
    }

    @Test("zirve metni değer, gün, saat ve süreç adını yazar")
    func peakText() {
        let utc = TimeZone(identifier: "UTC")!
        // 1970-01-01 Perşembe 00:00 UTC + 14 saat 30 dakika.
        let text = MetricHistory.peakText("En yüksek bellek", value: 91.6, sample: sample(52_200), process: "Chrome", timeZone: utc)
        #expect(text == "En yüksek bellek: %92, Per 14:30, Chrome")
        let noProcess = MetricHistory.peakText("En yüksek CPU", value: 5, sample: sample(0), process: nil, timeZone: utc)
        #expect(noProcess == "En yüksek CPU: %5, Per 00:00")
    }

    @Test("süre seçenekleri saniyeye çevrilir, bilinmeyen değer 1 saate düşer")
    func windows() {
        #expect(HistoryWindow.hour.seconds == 3_600)
        #expect(HistoryWindow.day.seconds == 86_400)
        #expect(HistoryWindow.week.seconds == MetricHistory.maxAge)
        #expect(HistoryWindow.allCases.map(\.label) == ["1 sa", "24 sa", "7 gün"])
        #expect(HistoryWindow(rawValue: "x") == nil)
    }
}

@Suite("MetricStore dosya")
struct MetricStoreTests {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("molebar-metrics-\(UUID().uuidString)")
            .appendingPathComponent("metrics.jsonl")
    }

    @Test("eklenen örnekler dosyadan geri okunur, klasör yoksa oluşturulur")
    func appendAndLoad() throws {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = MetricStore(file: file)
        store.append(sample(100))
        store.append(sample(200))
        let loaded = store.load(now: Date(timeIntervalSince1970: 300), maxAge: 1_000)
        #expect(loaded.map(\.time.timeIntervalSince1970) == [100, 200])
    }

    @Test("yüklemede eski satırlar dosyadan da silinir")
    func loadCompacts() throws {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = MetricStore(file: file)
        store.append(sample(100))
        store.append(sample(5_000))
        #expect(store.load(now: Date(timeIntervalSince1970: 5_100), maxAge: 1_000).count == 1)
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(MetricHistory.decode(text).count == 1)
    }

    @Test("dosya yoksa boş liste döner")
    func missingFile() {
        #expect(MetricStore(file: tempFile()).load(now: Date(), maxAge: 10).isEmpty)
    }
}
