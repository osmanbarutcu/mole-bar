import SwiftUI

/// Kullanım yüzdesine göre sistem renkleri.
func levelColor(_ percent: Double) -> Color {
    switch percent {
    case 90...: return .red
    case 75..<90: return .orange
    default: return .green
    }
}

extension View {
    /// macOS 26+: Liquid Glass. Eski sürümler: ince materyal + ince çerçeve.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 18, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            let glass: Glass = tint.map { Glass.regular.tint($0.opacity(0.22)) } ?? Glass.regular
            self.glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
                )
        }
    }

    @ViewBuilder
    func glassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

/// Cam öğeleri tek kapta toplar. macOS 26+ için birleşme ve performans sağlar.
struct GlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

struct RingGauge: View {
    let title: String
    let percent: Double
    var lineWidth: CGFloat = 7

    var body: some View {
        let color = levelColor(percent)
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(.primary.opacity(0.10), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: min(max(percent, 0), 100) / 100)
                    .stroke(
                        AngularGradient(colors: [color.opacity(0.55), color], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * min(max(percent, 1), 100) / 100)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: percent)
                Text(String(format: "%.0f", percent))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 58, height: 58)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 16)
    }
}

struct UsageBar: View {
    let percent: Double
    var height: CGFloat = 6
    var color: Color? = nil

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.10))
                Capsule()
                    .fill((color ?? levelColor(percent)).gradient)
                    .frame(width: max(proxy.size.width * min(max(percent, 0), 100) / 100, height))
                    .animation(.easeOut(duration: 0.5), value: percent)
            }
        }
        .frame(height: height)
    }
}

/// Dikey çekirdek çubuğu.
struct CoreBar: View {
    let index: Int
    let percent: Double

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    Capsule().fill(.primary.opacity(0.10))
                    Capsule()
                        .fill(levelColor(percent).gradient)
                        .frame(height: max(proxy.size.height * min(max(percent, 0), 100) / 100, 4))
                        .animation(.easeOut(duration: 0.4), value: percent)
                }
            }
            .frame(width: 10, height: 44)
            Text("\(index + 1)")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Değerleri 0–100 ölçeğinde çizgi olarak çizer.
struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                guard values.count > 1 else { return }
                let step = proxy.size.width / CGFloat(values.count - 1)
                for (index, value) in values.enumerated() {
                    let clamped = CGFloat(min(max(value, 0), 100)) / 100
                    let point = CGPoint(x: CGFloat(index) * step, y: proxy.size.height * (1 - clamped))
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
    }
}

struct CardHeader: View {
    let symbol: String
    let title: String
    var trailing: String = ""

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if !trailing.isEmpty {
                Text(trailing)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

struct RateChip: View {
    let symbol: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.callout)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.caption.weight(.medium).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 14)
    }
}
