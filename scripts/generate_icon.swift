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
        // Original open-notebook artwork, on a truly transparent canvas (no app tile).
        context.cgContext.clear(CGRect(x: 0, y: 0, width: p, height: p))
        func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat) -> NSBezierPath {
            NSBezierPath(roundedRect: NSRect(x: p*x, y: p*y, width: p*w, height: p*h),
                         xRadius: p*radius, yRadius: p*radius)
        }
        let lid = rounded(0.14, 0.30, 0.72, 0.52, 0.035)
        NSGradient(starting: NSColor(white: 0.83, alpha: 1), ending: NSColor(white: 0.39, alpha: 1))!
            .draw(in: lid, angle: -75)
        NSColor(white: 0.16, alpha: 1).setFill()
        rounded(0.154, 0.317, 0.692, 0.485, 0.024).fill()
        let screen = rounded(0.17, 0.344, 0.66, 0.431, 0.008)
        NSGradient(starting: NSColor(srgbRed: 0.05, green: 0.23, blue: 0.20, alpha: 1),
                   ending: NSColor(srgbRed: 0.015, green: 0.065, blue: 0.09, alpha: 1))!
            .draw(in: screen, angle: -70)
        if pixels >= 32 {
            // A tiny camera and abstract code strokes remain part of the illustration, not text.
            NSColor(white: 0.48, alpha: 1).setFill()
            rounded(0.493, 0.783, 0.014, 0.008, 0.004).fill()
            NSColor(white: 1, alpha: 0.08).setFill()
            rounded(0.185, 0.36, 0.085, 0.395, 0.008).fill()
            NSColor(srgbRed: 0.42, green: 0.88, blue: 0.64, alpha: 1).setFill()
            rounded(0.203, 0.706, 0.045, 0.013, 0.006).fill()
            for (row, width) in [0.36, 0.23, 0.31, 0.18].enumerated() {
                NSColor(srgbRed: 0.42, green: 0.88, blue: 0.64, alpha: row == 0 ? 1 : 0.65).setFill()
                rounded(row == 1 || row == 2 ? 0.35 : 0.31, 0.65 - CGFloat(row)*0.062,
                        CGFloat(width), 0.016, 0.008).fill()
            }
            NSColor(white: 1, alpha: 0.12).setFill()
            rounded(0.30, 0.698, 0.47, 0.039, 0.012).fill()
            let shine = NSBezierPath()
            shine.move(to: NSPoint(x: p*0.18, y: p*0.77))
            shine.line(to: NSPoint(x: p*0.71, y: p*0.77))
            shine.line(to: NSPoint(x: p*0.18, y: p*0.48))
            shine.close()
            NSColor(white: 1, alpha: 0.045).setFill()
            shine.fill()
        }
        let deck = NSBezierPath()
        deck.move(to: NSPoint(x: p*0.14, y: p*0.30))
        deck.line(to: NSPoint(x: p*0.86, y: p*0.30))
        deck.line(to: NSPoint(x: p*0.96, y: p*0.19))
        deck.line(to: NSPoint(x: p*0.04, y: p*0.19))
        deck.close()
        NSGradient(starting: NSColor(white: 0.79, alpha: 1), ending: NSColor(white: 0.53, alpha: 1))!
            .draw(in: deck, angle: -90)
        NSColor(white: 0.24, alpha: 1).setFill()
        rounded(0.19, 0.247, 0.62, 0.038, 0.008).fill()
        NSColor(white: 0.62, alpha: 1).setFill()
        rounded(0.40, 0.199, 0.20, 0.035, 0.008).fill()
        NSColor(white: 0.47, alpha: 1).setFill()
        rounded(0.04, 0.169, 0.92, 0.024, 0.012).fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let file = iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try rep.representation(using: .png, properties: [:])!.write(to: file)
    }
}
