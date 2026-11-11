import SwiftUI

/// Genel sayfasındaki geçmiş kartı. Veri `StatsModel.longHistory` içindedir (son 7 gün).
struct HistoryCard: View {
    @ObservedObject var stats: StatsModel
    @AppStorage("historyWindow") private var historyWindow = HistoryWindow.hour.rawValue

    var body: some View {
        let window = HistoryWindow(rawValue: historyWindow) ?? .hour
        let samples = MetricHistory.window(stats.longHistory, duration: window.seconds)
        if samples.count > 1 {
            let points = MetricHistory.downsample(samples, maxPoints: 120)
            let cpu = points.map(\.cpu)
            let ram = points.map(\.memory)
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(symbol: "chart.xyaxis.line", title: "Geçmiş")
                Picker("Süre", selection: $historyWindow) {
                    ForEach(HistoryWindow.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Sparkline(values: cpu, color: .blue)
                    .frame(height: 38)
                Sparkline(values: ram, color: .purple)
                    .frame(height: 38)
                HStack(spacing: 12) {
                    legend("CPU", color: .blue, average: cpu.reduce(0, +) / Double(cpu.count))
                    legend("RAM", color: .purple, average: ram.reduce(0, +) / Double(ram.count))
                }
                peakLine("En yüksek CPU", MetricHistory.peak(samples, \.cpu), process: \.topCPU)
                peakLine("En yüksek bellek", MetricHistory.peak(samples, \.memory), process: \.topMemory)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    @ViewBuilder
    private func peakLine(_ title: String, _ peak: (value: Double, sample: MetricSample)?,
                          process: KeyPath<MetricSample, String?>) -> some View {
        if let peak {
            Text(MetricHistory.peakText(title, value: peak.value, sample: peak.sample, process: peak.sample[keyPath: process]))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func legend(_ name: String, color: Color, average: Double) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(String(format: "%@ ort. %.0f%%", name, average))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

}
