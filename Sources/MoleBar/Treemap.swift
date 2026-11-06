import CoreGraphics
import Foundation
import SwiftUI

/// Squarified treemap yerleşimi (Bruls, Huizing, van Wijk). Alan değerle orantılıdır.
enum Treemap {
    private struct Item { let index: Int; let area: Double }

    /// Her değer için bir dikdörtgen döndürür. Sıfır veya negatif değer `.zero` alır. Sıra girdiyle aynıdır.
    static func layout(values: [Double], in bounds: CGRect) -> [CGRect] {
        var result = Array(repeating: CGRect.zero, count: values.count)
        let sorted = values.enumerated().filter { $0.element > 0 }.sorted { $0.element > $1.element }
        let total = sorted.reduce(0) { $0 + $1.element }
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return result }
        let scale = Double(bounds.width * bounds.height) / total
        var rest = sorted.map { Item(index: $0.offset, area: $0.element * scale) }[...]
        var free = bounds

        while !rest.isEmpty {
            let side = Double(min(free.width, free.height))
            var row = [rest.removeFirst()]
            var best = worstRatio(row, side: side)
            while let next = rest.first {
                let candidate = worstRatio(row + [next], side: side)
                if candidate > best { break }
                row.append(rest.removeFirst())
                best = candidate
            }
            free = place(row, in: free, into: &result, isLast: rest.isEmpty)
        }
        return result
    }

    /// Satırdaki en kötü en/boy oranı. Küçük değer kareye yakın demektir.
    private static func worstRatio(_ row: [Item], side: Double) -> Double {
        let sum = row.reduce(0) { $0 + $1.area }
        guard let maxArea = row.map(\.area).max(), let minArea = row.map(\.area).min(), sum > 0, minArea > 0 else { return .infinity }
        return max(side * side * maxArea / (sum * sum), sum * sum / (side * side * minArea))
    }

    /// Satırı serbest alanın kısa kenarı boyunca yerleştirir, kalan alanı döndürür.
    private static func place(_ row: [Item], in free: CGRect, into result: inout [CGRect], isLast: Bool) -> CGRect {
        let sum = row.reduce(0) { $0 + $1.area }
        if free.width >= free.height {
            let thickness = isLast ? free.width : CGFloat(sum) / free.height
            var y = free.minY
            for item in row {
                let height = free.height * CGFloat(item.area / sum)
                result[item.index] = CGRect(x: free.minX, y: y, width: thickness, height: height)
                y += height
            }
            return CGRect(x: free.minX + thickness, y: free.minY, width: free.width - thickness, height: free.height)
        } else {
            let thickness = isLast ? free.height : CGFloat(sum) / free.width
            var x = free.minX
            for item in row {
                let width = free.width * CGFloat(item.area / sum)
                result[item.index] = CGRect(x: x, y: free.minY, width: width, height: thickness)
                x += width
            }
            return CGRect(x: free.minX, y: free.minY + thickness, width: free.width, height: free.height - thickness)
        }
    }
}

/// Analiz sayfasının harita görünümü. Karo alanı boyutla orantılıdır. Klasöre tıklamak içine girer.
struct TreemapView: View {
    let entries: [DiskEntry]
    let onOpen: (DiskEntry) -> Void

    private static let gap: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let rects = Treemap.layout(values: entries.map { Double($0.bytes) }, in: CGRect(origin: .zero, size: proxy.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    let rect = rects[index]
                    if rect != .zero { tile(entry, rect) }
                }
            }
        }
    }

    private func tile(_ entry: DiskEntry, _ rect: CGRect) -> some View {
        let inner = rect.insetBy(dx: Self.gap / 2, dy: Self.gap / 2)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(entry.isDirectory ? Color.accentColor.opacity(0.28) : Color.secondary.opacity(0.22))
            if inner.width > 56, inner.height > 34 {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: entry.name).font(.caption.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    Text(formatBytes(entry.bytes)).font(.caption2.monospacedDigit()).foregroundStyle(.primary.opacity(0.75))
                }
                .padding(6)
            }
        }
        .frame(width: max(inner.width, 0), height: max(inner.height, 0))
        .offset(x: inner.minX, y: inner.minY)
        .contentShape(Rectangle())
        .onTapGesture { onOpen(entry) }
        .help("\(entry.name): \(formatBytes(entry.bytes))")
    }
}
