// Uygulama simgesini çizer. Kullanım:
//   swift scripts/make-icon.swift Resources/AppIcon.iconset
//   iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

func render(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = context
    let cg = context.cgContext
    let u = CGFloat(pixels) / 1024

    // Gövde: macOS simge ızgarası (824 piksel, köşe 185).
    let body = CGRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    let path = CGPath(roundedRect: body, cornerWidth: 185 * u, cornerHeight: 185 * u, transform: nil)

    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -12 * u), blur: 24 * u,
                 color: NSColor.black.withAlphaComponent(0.35).cgColor)
    cg.addPath(path)
    cg.setFillColor(NSColor(red: 0.07, green: 0.10, blue: 0.18, alpha: 1).cgColor)
    cg.fillPath()
    cg.restoreGState()

    cg.saveGState()
    cg.addPath(path)
    cg.clip()
    let colors = [
        NSColor(red: 0.23, green: 0.31, blue: 0.47, alpha: 1).cgColor,
        NSColor(red: 0.06, green: 0.09, blue: 0.17, alpha: 1).cgColor
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 924 * u), end: CGPoint(x: 0, y: 100 * u), options: [])
    }

    // Gösterge halkası: 270 derece iz, %72 dolu yay.
    let center = CGPoint(x: 512 * u, y: 512 * u)
    let radius = 255 * u
    let startAngle = CGFloat.pi * 5 / 4
    let sweep = CGFloat.pi * 3 / 2
    cg.setLineCap(.round)
    cg.setLineWidth(74 * u)
    cg.setStrokeColor(NSColor.white.withAlphaComponent(0.14).cgColor)
    cg.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: startAngle - sweep, clockwise: true)
    cg.strokePath()
    cg.setStrokeColor(NSColor(red: 0.20, green: 0.83, blue: 0.60, alpha: 1).cgColor)
    cg.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: startAngle - sweep * 0.72, clockwise: true)
    cg.strokePath()

    // Merkez: üç çubuk (CPU, bellek, disk).
    let heights: [CGFloat] = [150, 230, 110]
    for (index, height) in heights.enumerated() {
        let x = (512 + CGFloat(index - 1) * 82 - 24) * u
        let bar = CGRect(x: x, y: (512 - 115) * u, width: 48 * u, height: height * u)
        cg.addPath(CGPath(roundedRect: bar, cornerWidth: 24 * u, cornerHeight: 24 * u, transform: nil))
        cg.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
        cg.fillPath()
    }
    cg.restoreGState()

    return rep.representation(using: .png, properties: [:])
}

let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for entry in sizes {
    guard let data = render(pixels: entry.pixels) else { fatalError("Çizim başarısız: \(entry.name)") }
    try data.write(to: URL(fileURLWithPath: output).appendingPathComponent(entry.name + ".png"))
}
print("Yazıldı: \(output)")
