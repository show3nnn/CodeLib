import Testing
@testable import LearningCore

struct GreetingPlaybackTests {
    @Test func everyGreetingTypesHoldsFadesAndFinishesWithoutLooping() {
        var playback = GreetingPlayback()
        var visited: Set<String> = []
        var fades = 0
        for _ in 0..<1000 {
            visited.insert(playback.greeting.id)
            #expect(playback.greeting.code.hasPrefix(playback.visibleText))
            let previous = playback.phase
            playback.advance()
            if playback.phase == .fading && previous != .fading { fades += 1 }
        }
        #expect(visited == Set(ProgrammingGreeting.all.map(\.id)))
        #expect(fades == 4 && playback.isFinished)
        #expect(playback.visibleText == ProgrammingGreeting.all.last?.code)
        let finalIndex = playback.index
        playback.advance()
        #expect(playback.index == finalIndex)
    }
    @Test func skipDuringTypingOrFadeIsImmediateAndStable() {
        for ticks in [0, 4, 60, 100, 200] {
            var playback = GreetingPlayback()
            for _ in 0..<ticks { playback.advance() }
            let greeting = playback.greeting
            playback.skip()
            #expect(playback.isFinished && playback.visibleText == greeting.code)
            for _ in 0..<100 { playback.advance() }
            #expect(playback.greeting.id == greeting.id && playback.visibleText == greeting.code)
        }
    }
    @Test func manualAccessibleSelectionDoesNotRestartAnimation() {
        var playback = GreetingPlayback()
        for greeting in ProgrammingGreeting.all {
            playback.selectGreeting(greeting.id)
            #expect(playback.isFinished && playback.visibleText == greeting.code)
            playback.advance()
            #expect(playback.greeting.id == greeting.id)
        }
        playback.selectGreeting("unknown")
        #expect(playback.greeting.id == "java")
    }
}
