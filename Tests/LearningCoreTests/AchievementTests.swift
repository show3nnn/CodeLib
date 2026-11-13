import Foundation
import Testing
@testable import LearningCore

struct AchievementTests {
    @Test func catalogHas24ObtainableLocalizedDefinitions() throws {
        let course = try Course.bundled()
        try AchievementCatalog.validate(course: course)
        #expect(AchievementCatalog.all.count == 24)
        #expect(AchievementCatalog.all.allSatisfy { !$0.title(locale: "en").isEmpty && !$0.detail(locale: "ru").isEmpty })
        var document = ProgressDocument()
        document.achievements = AchievementState()
        document.achievements?.studyDays = ["2026-11-01", "2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05"]
        for task in course.exercises {
            var state = ExerciseProgress()
            state.completion = task.kind == .code ? .selfReviewed : .automatic
            state.attempts = task.kind == .code ? 0 : 1
            if task.kind == .code { state.draft = "// черновик" }
            document.exercises[task.id] = state
        }
        let added = AchievementEngine.reconcile(&document, course: course, now: Date(timeIntervalSince1970: 100), historical: false)
        #expect(added.count == 24)
        #expect(AchievementEngine.reconcile(&document, course: course, now: Date(), historical: false).isEmpty)
    }

    @Test func onlyRealCompletionTypesCountAndUnknownIDsDoNot() throws {
        let course = try Course.bundled()
        let code = try #require(course.exercises.first { $0.kind == .code })
        var document = ProgressDocument()
        var state = ExerciseProgress()
        state.draft = "int main() {}"
        document.exercises[code.id] = state
        let first = AchievementEngine.reconcile(&document, course: course, now: Date(), historical: false)
        #expect(first == ["award.draft"])
        state.completion = .selfReviewed
        document.exercises[code.id] = state
        document.exercises["future.unknown.task"] = state
        let added = AchievementEngine.reconcile(&document, course: course, now: Date(), historical: false)
        #expect(added.contains("award.selfreview"))
        #expect(!added.contains("award.checked") && !added.contains("award.firsttry"))
        #expect(document.achievements?.awards.count == 2)
    }

    @Test func historicalBackfillPreservesUnknownAwardsAndNeverRevokes() throws {
        let course = try Course.bundled()
        var document = ProgressDocument()
        var state = ExerciseProgress()
        state.completion = .automatic
        state.attempts = 1
        let first = try #require(course.exercises.first { $0.kind == .choice })
        document.exercises[first.id] = state
        let recognized = Date(timeIntervalSince1970: 1234)
        let ids = AchievementEngine.reconcile(&document, course: course, now: recognized, historical: true)
        #expect(ids.contains("award.checked"))
        #expect(document.achievements?.awards["award.checked"]?.historical == true)
        document.achievements?.awards["future.award"] = AchievementAward(recognizedAt: recognized, historical: true)
        document.exercises.removeAll()
        #expect(AchievementEngine.reconcile(&document, course: course, now: Date(), historical: false).isEmpty)
        let restored = try ProgressStore.decode(JSONEncoder().encode(document))
        #expect(restored.achievements?.awards["future.award"] != nil)
        #expect(restored.achievements?.awards["award.checked"]?.recognizedAt == recognized)
    }

    @Test func streakUsesCalendarDatesAcrossDSTLeapDaysAndGaps() throws {
        #expect(AchievementEngine.longestStreak(["2024-02-28", "2024-02-29", "2024-03-01"]) == 3)
        #expect(AchievementEngine.longestStreak(["2026-03-07", "2026-03-08", "2026-03-09"]) == 3)
        #expect(AchievementEngine.longestStreak(["2026-11-01", "2026-11-03", "2026-11-04"]) == 2)
        var state = AchievementState()
        state.studyDays = ["2026-02-30"]
        #expect(throws: (any Error).self) { try AchievementEngine.validate(state) }
        state.studyDays = ["2026-2-03"]
        #expect(throws: (any Error).self) { try AchievementEngine.validate(state) }
    }

    @Test func hintFreeAndFirstTryHaveDistinctEvidence() throws {
        let course = try Course.bundled()
        var document = ProgressDocument()
        for task in course.exercises.prefix(10) {
            var state = ExerciseProgress()
            state.completion = .selfReviewed
            state.hintLevel = 1
            document.exercises[task.id] = state
        }
        let ids = AchievementEngine.reconcile(&document, course: course, now: Date(), historical: false)
        #expect(!ids.contains("award.hintfree") && !ids.contains("award.firsttry"))
    }

    @Test func schemaOneWithoutAchievementsGetsSafeDefaults() throws {
        let bytes = try JSONEncoder().encode(ProgressDocument())
        let value = try JSONSerialization.jsonObject(with: bytes)
        var json = try #require(value as? [String: Any])
        var preferences = try #require(json["preferences"] as? [String: Any])
        preferences.removeValue(forKey: "achievementSounds")
        json["preferences"] = preferences
        let document = try ProgressStore.decode(JSONSerialization.data(withJSONObject: json))
        #expect(document.achievements == nil && document.preferences.achievementSounds)
    }
}
