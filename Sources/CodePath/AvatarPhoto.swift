import AppKit
import ImageIO
import LearningCore
import SwiftUI

@MainActor
enum AvatarPhoto {
    static func load(_ url: URL) throws -> NSImage {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 12 * 1024 * 1024,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16_000, height <= 16_000,
              Double(width) * Double(height) <= 40_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024
              ] as CFDictionary) else {
            throw PhotoFailure.invalidSource
        }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    static func crop(_ image: NSImage, zoom: Double, x: Double, y: Double) throws -> Data {
        guard image.size.width > 0, image.size.height > 0,
              (1...3).contains(zoom), (-1...1).contains(x), (-1...1).contains(y),
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { throw PhotoFailure.cropFailed }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        let scale = 256 / min(image.size.width, image.size.height) * zoom
        let width = image.size.width * scale, height = image.size.height * scale
        image.draw(in: NSRect(x: (256-width)/2 + x*(width-256)/2, y: (256-height)/2 - y*(height-256)/2,
                              width: width, height: height), from: .zero, operation: .copy, fraction: 1)
        guard let data = rep.representation(using: .png, properties: [:]), data.count <= 262_144 else {
            throw PhotoFailure.encodingFailed
        }
        return data
    }
}

struct AvatarCropView: View {
    let image: NSImage
    let save: (Data) -> Void
    @State private var zoom = 1.0
    @State private var x = 0.0
    @State private var y = 0.0
    @State private var error: AppFailure?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 18) {
            Text("Кадрирование аватара").font(.title2.bold())
            let scale = 256 / min(image.size.width, image.size.height) * zoom
            let width = image.size.width * scale, height = image.size.height * scale
            Image(nsImage: image).resizable().frame(width: width, height: height)
                .offset(x: x*(width-256)/2, y: y*(height-256)/2)
                .frame(width: 256, height: 256).clipped().clipShape(Circle())
            Slider(value: $zoom, in: 1...3) { Text("Масштаб") }
            Slider(value: $x, in: -1...1) { Text("По горизонтали") }
            Slider(value: $y, in: -1...1) { Text("По вертикали") }
            if let error { Text(error.resource()).foregroundStyle(.red) }
            HStack {
                Button("Отмена") { dismiss() }
                Spacer()
                Button("Использовать фото") {
                    do { save(try AvatarPhoto.crop(image, zoom: zoom, x: x, y: y)) }
                    catch { self.error = AppFailure(error) }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 410)
    }
}
