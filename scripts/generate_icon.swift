import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = root.appendingPathComponent("CodePath.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let p = CGFloat(pixels)
        let rect = NSRect(x: p * 0.08, y: p * 0.08, width: p * 0.84, height: p * 0.84)
        let path = NSBezierPath(roundedRect: rect, xRadius: p * 0.2, yRadius: p * 0.2)
        NSGradient(starting: NSColor(srgbRed: 0.09, green: 0.22, blue: 0.31, alpha: 1),
                   ending: NSColor(srgbRed: 0.03, green: 0.09, blue: 0.16, alpha: 1))!.draw(in: path, angle: -70)
        let text = "{ }" as NSString
        let font = NSFont.monospacedSystemFont(ofSize: p * 0.38, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font,
            .foregroundColor: NSColor(srgbRed: 0.43, green: 0.9, blue: 0.77, alpha: 1)]
        let bounds = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (p - bounds.width) / 2, y: (p - bounds.height) / 2 + p * 0.01), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let file = iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try rep.representation(using: .png, properties: [:])!.write(to: file)
    }
}
