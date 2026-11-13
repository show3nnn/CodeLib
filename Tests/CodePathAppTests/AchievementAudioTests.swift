import AppKit
import Foundation
import LearningCore
import Testing
@testable import CodePathApp

@MainActor struct AchievementAudioTests {
    @Test func allAwardSymbolsExistInTheNativeSymbolCatalog() {
        for item in AchievementCatalog.all {
            #expect(NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil) != nil, "\(item.symbol)")
        }
    }
    @Test func originalSoundLoadsAndDisabledPlaybackHasNoEffect() throws {
        let url = try #require(AchievementCatalog.soundURL)
        let data = try Data(contentsOf: url)
        #expect(String(data: data.prefix(4), encoding: .ascii) == "RIFF")
        #expect(data.count > 1000 && data.count < 20000)
        #expect(NSSound(contentsOf: url, byReference: true) != nil)
        #expect(!AchievementAudio.play(enabled: false))
    }
}
