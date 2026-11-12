import Foundation
import Testing
@testable import LearningCore

struct ProfileTests {
    @Test func unicodeNamesNormalizeWithoutBreakingEmoji() throws {
        let raw = "  e\u{301} 🚀  "
        let name = LocalProfile.normalizedName(raw)
        #expect(name == "é 🚀")
        let profile = LocalProfile(nickname: name)
        try profile.validate()
        #expect(profile.initial == "É")
        try LocalProfile(nickname: "👩🏽‍💻").validate()
        try LocalProfile(nickname: String(repeating: "я", count: 30)).validate()
    }
    @Test func invalidNamesAndPhotosAreRejected() {
        for name in ["", " ", "\n", "А\nБ", "\u{200B}", "a\u{202E}b", String(repeating: "x", count: 31), "Имя "] {
            #expect(throws: (any Error).self) { try LocalProfile(nickname: name).validate() }
        }
        #expect(throws: (any Error).self) { try LocalProfile(nickname: "Фото", avatar: .photo, photo: Data("broken".utf8)).validate() }
        #expect(throws: (any Error).self) { try LocalProfile(nickname: "Фото", photo: Data([1])).validate() }
    }
    @Test func startupOrderSeparatesFirstSetupFromUpdates() throws {
        var document = ProgressDocument()
        let current = try #require(NumericVersion(rawValue: "0.1.2"))
        #expect(StartupRoute.resolve(document: document, current: current) == .onboarding)
        document.profile = LocalProfile(nickname: "Анна")
        #expect(StartupRoute.resolve(document: document, current: current) == .onboarding)
        var setup = OnboardingState()
        setup.draft = document.profile!
        setup.completedVersion = 1
        document.onboarding = setup
        #expect(StartupRoute.resolve(document: document, current: current) == .releaseHistory)
        document.lastViewedRelease = current
        #expect(StartupRoute.resolve(document: document, current: current) == .workspace)
        document.lastViewedRelease = NumericVersion(rawValue: "0.9.0")
        #expect(StartupRoute.resolve(document: document, current: current) == .workspace)
    }
    @Test func legacyAndPartialSetupRoundTripWithoutLosingProgress() throws {
        var document = ProgressDocument()
        var state = ExerciseProgress()
        state.draft = ""
        state.completion = .selfReviewed
        document.exercises["future.stable.id"] = state
        let old = try ProgressStore.decode(JSONEncoder().encode(document))
        #expect(old.profile == nil && old.onboarding == nil)
        var setup = OnboardingState()
        setup.step = .appearance
        setup.draft = LocalProfile(nickname: "Ученик", avatar: .mountain)
        document.onboarding = setup
        let restored = try ProgressStore.decode(JSONEncoder().encode(document))
        #expect(restored.onboarding?.step == .appearance)
        #expect(restored.onboarding?.draft.nickname == "Ученик")
        #expect(restored.completed("future.stable.id"))
        #expect(restored.exercises["future.stable.id"]?.draft == "")
        #expect(restored.schemaVersion == 1)
    }
}
