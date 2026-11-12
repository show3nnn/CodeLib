import AppKit
import Foundation
import LearningCore
import Testing
@testable import CodePathApp

@MainActor struct AvatarPhotoTests {
    @Test func localPhotoLoadingAndPersistenceUseOnlyCroppedPNG() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/test-data/photo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let image = NSImage(size: NSSize(width: 300, height: 500), flipped: false) { rect in
            NSColor.blue.setFill(); rect.fill(); return true
        }
        let source = root.appendingPathComponent("photo.png")
        let data = try AvatarPhoto.crop(image, zoom: 1.5, x: 0, y: 1)
        try data.write(to: source)
        let loaded = try AvatarPhoto.load(source)
        #expect(loaded.size.width == 256 && loaded.size.height == 256)
        let store = try ProgressStore(url: root.appendingPathComponent("progress.json"))
        try store.update { $0.profile = LocalProfile(nickname: "Фото", avatar: .photo, photo: data) }
        #expect(try ProgressStore(url: store.url).document.profile?.photo == data)
        try Data("not an image".utf8).write(to: source)
        #expect(throws: (any Error).self) { try AvatarPhoto.load(source) }
    }

    @Test func cropCreatesBoundedPNGWithoutOriginalMetadata() throws {
        let image = NSImage(size: NSSize(width: 600, height: 400), flipped: false) { rect in
            NSColor.green.setFill()
            rect.fill()
            return true
        }
        for (zoom, x, y) in [(1.0, 0.0, 0.0), (3.0, -1.0, 1.0)] {
            let data = try AvatarPhoto.crop(image, zoom: zoom, x: x, y: y)
            let rep = try #require(NSBitmapImageRep(data: data))
            #expect(rep.pixelsWide == 256 && rep.pixelsHigh == 256)
            try LocalProfile(nickname: "Фото", avatar: .photo, photo: data).validate()
            #expect(rep.colorAt(x: 128, y: 128)?.greenComponent == 1)
        }
        #expect(throws: (any Error).self) { try AvatarPhoto.crop(image, zoom: 4, x: 0, y: 0) }
    }
}
