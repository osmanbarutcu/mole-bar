import AppKit

/// Menü çubuğu için küçük çizgi grafiği. Şablon görüntü üretir, açık ve koyu menü çubuğunda sistem renklendirir.
enum MenuBarGraph {
    /// Seriye değer ekler ve yalnızca son `limit` değeri tutur.
    static func push(_ values: [Double], _ value: Double, limit: Int) -> [Double] {
        Array((values + [value]).suffix(limit))
    }

    /// Değerleri alttan yukarı koordinata çevirir. 0 alt kenar, `maximum` üst kenardır. Aralık dışı değer kırpılır.
    static func points(values: [Double], width: CGFloat, height: CGFloat, maximum: Double = 100) -> [CGPoint] {
        guard values.count >= 2, maximum > 0 else { return [] }
        let step = width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let ratio = min(max(value / maximum, 0), 1)
            return CGPoint(x: step * CGFloat(index), y: height * CGFloat(ratio))
        }
    }

    /// Şablon `NSImage`. Çizgi 1,5 pt, altı hafif dolgulu.
    static func image(values: [Double], size: NSSize = NSSize(width: 34, height: 14)) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            // Çizgi kenarlarda kesilmesin diye 1 pt iç boşluk bırakılır.
            let inset: CGFloat = 1
            let area = NSSize(width: size.width - inset * 2, height: size.height - inset * 2)
            let points = points(values: values, width: area.width, height: area.height)
                .map { CGPoint(x: $0.x + inset, y: $0.y + inset) }
            guard let first = points.first, let last = points.last else { return true }

            let fill = NSBezierPath()
            fill.move(to: CGPoint(x: first.x, y: inset))
            for point in points { fill.line(to: point) }
            fill.line(to: CGPoint(x: last.x, y: inset))
            fill.close()
            NSColor.black.withAlphaComponent(0.25).setFill()
            fill.fill()

            let line = NSBezierPath()
            line.move(to: first)
            for point in points.dropFirst() { line.line(to: point) }
            line.lineWidth = 1.5
            line.lineJoinStyle = .round
            NSColor.black.setStroke()
            line.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
