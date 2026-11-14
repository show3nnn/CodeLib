import Foundation
import Testing
@testable import LearningCore

struct LocalizedContentTests {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func data(_ path: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(path))
    }

    @Test func snapshotRequiresEveryReviewedResource() throws {
        let course = try data("Sources/LearningCore/Resources/course.json")
        let catalog = try data("Sources/LearningCore/Resources/catalog.json")
        let history = try data("Sources/LearningCore/Resources/releases.json")
        let courseDraft = try JSONDecoder().decode(CourseTranslation.self, from: data("localization/drafts/course.en.json"))
        let catalogDraft = try JSONDecoder().decode(ResourceTranslation.self, from: data("localization/drafts/catalog.en.json"))
        let historyDraft = try JSONDecoder().decode(ResourceTranslation.self, from: data("localization/drafts/releases.en.json"))
        // Synthetic statuses exercise the gate only; authored translations remain drafts.
        let reviewedCourse = CourseTranslation(formatVersion: courseDraft.formatVersion, courseID: courseDraft.courseID,
            locale: courseDraft.locale, sourceSHA256: courseDraft.sourceSHA256, status: .reviewed, texts: courseDraft.texts)
        func reviewed(_ draft: ResourceTranslation) -> ResourceTranslation {
            ResourceTranslation(formatVersion: draft.formatVersion, resource: draft.resource, locale: draft.locale,
                                sourceSHA256: draft.sourceSHA256, status: .reviewed, texts: draft.texts)
        }
        let russian = try LocalizedContent.load(locale: .russian, courseData: course, catalogData: catalog, historyData: history)
        #expect(russian.locale == .russian)
        #expect(throws: ContentError.translationNotReady(missing: 0, unknown: 0)) {
            try LocalizedContent.load(locale: .english, courseData: course, catalogData: catalog, historyData: history,
                                      courseTranslation: courseDraft, catalogTranslation: catalogDraft, historyTranslation: historyDraft)
        }
        #expect(throws: ContentError.resourceTranslationUnreviewed) {
            try LocalizedContent.load(locale: .english, courseData: course, catalogData: catalog, historyData: history,
                                      courseTranslation: reviewedCourse, catalogTranslation: catalogDraft, historyTranslation: historyDraft)
        }
        #expect(throws: ContentError.resourceTranslationUnreviewed) {
            try LocalizedContent.load(locale: .english, courseData: course, catalogData: catalog, historyData: history,
                                      courseTranslation: reviewedCourse, catalogTranslation: reviewed(catalogDraft), historyTranslation: historyDraft)
        }
        #expect(throws: ContentError.resourceTranslationUnavailable(resource: "releases", locale: "en")) {
            try LocalizedContent.load(locale: .english, courseData: course, catalogData: catalog, historyData: history,
                                      courseTranslation: reviewedCourse, catalogTranslation: reviewed(catalogDraft))
        }
        var missingTexts = historyDraft.texts
        missingTexts.removeValue(forKey: try #require(missingTexts.keys.first))
        let incomplete = ResourceTranslation(formatVersion: historyDraft.formatVersion, resource: .releases,
            locale: .english, sourceSHA256: historyDraft.sourceSHA256, status: .reviewed, texts: missingTexts)
        #expect(throws: ContentError.resourceTranslationNotReady(missing: 1, unknown: 0)) {
            try LocalizedContent.load(locale: .english, courseData: course, catalogData: catalog, historyData: history,
                                      courseTranslation: reviewedCourse, catalogTranslation: reviewed(catalogDraft),
                                      historyTranslation: incomplete)
        }
        let stale = ResourceTranslation(formatVersion: historyDraft.formatVersion, resource: .releases,
            locale: .english, sourceSHA256: "stale", status: .reviewed, texts: historyDraft.texts)
        #expect(throws: ContentError.invalidResourceTranslationSource) {
            try LocalizedContent.load(locale: .english, courseData: course, catalogData: catalog, historyData: history,
                                      courseTranslation: reviewedCourse, catalogTranslation: reviewed(catalogDraft),
                                      historyTranslation: stale)
        }
        let store = try ProgressStore(url: root.appendingPathComponent(".build/test-data/snapshot-\(UUID().uuidString)/progress.json"))
        try store.update { document in
            document.profile = LocalProfile(nickname: "Пилот", avatar: .star)
            var progress = ExerciseProgress()
            progress.draft = ""
            progress.answer = "answer"
            document.exercises["unknown.exercise"] = progress
            document.lastExerciseID = "unknown.exercise"
            document.lessonPositions = ["unknown.lesson": "unknown.exercise"]
            var achievements = AchievementState()
            achievements.awards["unknown.award"] = AchievementAward(recognizedAt: Date(timeIntervalSince1970: 1000), historical: true)
            document.achievements = achievements
        }
        let saved = try Data(contentsOf: store.url)
        let english = try LocalizedContent.load(locale: .english, courseData: course, catalogData: catalog, historyData: history,
                                                courseTranslation: reviewedCourse, catalogTranslation: reviewed(catalogDraft),
                                                historyTranslation: reviewed(historyDraft))
        #expect(english.locale == .english)
        #expect(english.course.id == russian.course.id)
        #expect(english.course.lessons.first?.title != russian.course.lessons.first?.title)
        #expect(english.catalog.entries.map(\.id) == russian.catalog.entries.map(\.id))
        #expect(english.history.releases.map(\.version) == russian.history.releases.map(\.version))
        #expect(try Data(contentsOf: store.url) == saved)
        let reopened = try ProgressStore(url: store.url).document
        #expect(reopened.exercises["unknown.exercise"]?.draft == "")
        #expect(reopened.exercises["unknown.exercise"]?.answer == "answer")
        #expect(reopened.lastExerciseID == "unknown.exercise")

        // Simulate the future caller's ordering without enabling any UI language.
        // Assignment occurs only after both preparation and persistence succeed.
        var active = try russian.commitContentSelection(to: store)
        let russianBytes = try Data(contentsOf: store.url)
        #expect(throws: ContentError.translationNotReady(missing: 0, unknown: 0)) {
            active = try LocalizedContent.load(locale: .english, courseData: course, catalogData: catalog, historyData: history,
                courseTranslation: courseDraft, catalogTranslation: catalogDraft, historyTranslation: historyDraft)
                .commitContentSelection(to: store)
        }
        #expect(active.locale == .russian)
        #expect(try Data(contentsOf: store.url) == russianBytes)
        active = try english.commitContentSelection(to: store)
        #expect(active.locale == .english)
        #expect(try ProgressStore(url: store.url).document.preferences.preferredLanguage == "en")
        let staleStore = try ProgressStore(url: store.url)
        active = try russian.commitContentSelection(to: store)
        let currentBytes = try Data(contentsOf: store.url)
        #expect(throws: StorageError.conflictingRevision) {
            active = try english.commitContentSelection(to: staleStore)
        }
        #expect(active.locale == .russian)
        #expect(try Data(contentsOf: store.url) == currentBytes)
        let final = try ProgressStore(url: store.url).document
        #expect(final.preferences.preferredLanguage == "ru")
        #expect(final.profile == reopened.profile)
        #expect(final.lessonPositions == reopened.lessonPositions)
        #expect(final.achievements?.awards["unknown.award"]?.recognizedAt == Date(timeIntervalSince1970: 1000))
        #expect(final.exercises["unknown.exercise"]?.draft == "")
        #expect(final.exercises["unknown.exercise"]?.answer == "answer")
    }
}
