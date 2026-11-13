import Foundation
import Testing
@testable import LearningCore

struct CourseTranslationTests {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    private func source() throws -> Data { try Data(contentsOf: root.appendingPathComponent("Sources/LearningCore/Resources/course.json")) }
    private func draft() throws -> CourseTranslation {
        try JSONDecoder().decode(CourseTranslation.self, from: Data(contentsOf: root.appendingPathComponent("localization/drafts/course.en.json")))
    }
    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    @Test func authoredDraftHasAccurateCoverageButCannotBecomeAnAppLanguage() throws {
        let source = try source()
        let translation = try draft()
        let report = try translation.coverage(for: source)
        #expect(report.translated > 40 && report.translated < report.total)
        #expect(report.unknown.isEmpty && !report.isComplete)
        let base = try JSONDecoder().decode(Course.self, from: source)
        let firstLessonKeys = Set(CourseTranslation.sourceTexts(in: base).keys.filter { $0.hasPrefix("cpp.first.") })
        #expect(firstLessonKeys.isSubset(of: Set(translation.texts.keys)))
        #expect(throws: (any Error).self) { try translation.apply(to: source) }
        #expect(throws: (any Error).self) { try Course.bundled(locale: .english) }
        let preview = try translation.developerPreview(from: source)
        #expect(preview.lessons.first?.title == "Programs and main")
        #expect(preview.exercises.first?.title == "Station beacon")
        #expect(try Course.bundled().lessons.first?.title != preview.lessons.first?.title)
    }

    @Test func translationDoesNotChangeIDsCodeAnswersOrFixtures() throws {
        let source = try source()
        let base = try JSONDecoder().decode(Course.self, from: source)
        let preview = try draft().developerPreview(from: source)
        #expect(base.id == preview.id && base.version == preview.version && base.language == preview.language)
        #expect(base.sections.map(\.id) == preview.sections.map(\.id))
        #expect(base.lessons.map(\.id) == preview.lessons.map(\.id))
        #expect(base.lessons.map(\.prerequisites) == preview.lessons.map(\.prerequisites))
        #expect(base.lessons.map(\.example) == preview.lessons.map(\.example))
        for (original, translated) in zip(base.exercises, preview.exercises) {
            #expect(original.id == translated.id && original.kind == translated.kind && original.difficulty == translated.difficulty)
            #expect(original.starter == translated.starter && original.solution == translated.solution)
            #expect(original.answer == translated.answer && original.choices == translated.choices)
            #expect(try encoded(original.testCases) == encoded(translated.testCases))
        }
    }

    @Test func progressAndChoiceCheckingSurviveDisplayLanguageChanges() throws {
        let source = try source()
        let base = try JSONDecoder().decode(Course.self, from: source)
        let preview = try draft().developerPreview(from: source)
        let original = try #require(base.exercises.first { $0.kind == .choice })
        let translated = try #require(preview.exercises.first { $0.id == original.id })
        let answer = try #require(original.answer)
        #expect(translated.choiceLabel(for: answer) != answer)
        #expect(translated.answerLabel == translated.choiceLabel(for: answer))
        #expect(AnswerChecker.check(answer, for: translated) == true)
        #expect(AnswerChecker.check(translated.choiceLabel(for: answer), for: translated) == false)
        let folder = root.appendingPathComponent(".build/test-data/locale-\(UUID().uuidString)")
        let store = try ProgressStore(url: folder.appendingPathComponent("progress.json"))
        try store.update {
            $0.lastExerciseID = original.id
            var progress = ExerciseProgress()
            progress.answer = answer; progress.draft = ""; progress.completion = .automatic; progress.hintLevel = 2
            $0.exercises[original.id] = progress
            $0.exercises["future.unknown.id"] = ExerciseProgress()
        }
        let reopened = try ProgressStore(url: store.url).document
        #expect(reopened.completedCount(in: base) == reopened.completedCount(in: preview))
        #expect(reopened.exercises[original.id]?.draft == "")
        #expect(reopened.exercises[original.id]?.hintLevel == 2)
        #expect(reopened.exercises["future.unknown.id"] != nil)
        #expect(AnswerChecker.check(reopened.exercises[original.id]!.answer, for: translated) == true)
    }

    @Test func staleUnknownEmptyAndUnreviewedTranslationsAreRejected() throws {
        let data = try source()
        let draft = try draft()
        let completeTexts = CourseTranslation.sourceTexts(in: try Course.bundled())
        func translation(_ texts: [String: String], digest: String? = nil, status: CourseTranslation.Status = .reviewed, id: String = "cpp-foundations") -> CourseTranslation {
            CourseTranslation(formatVersion: 1, courseID: id, locale: .english, sourceSHA256: digest ?? CourseTranslation.digest(data), status: status, texts: texts)
        }
        #expect(throws: (any Error).self) { try translation(completeTexts, digest: "stale").apply(to: data) }
        #expect(throws: (any Error).self) { try translation(completeTexts, status: .draft).apply(to: data) }
        #expect(throws: (any Error).self) { try translation(completeTexts, id: "another-course").apply(to: data) }
        var unknown = draft.texts
        unknown["cpp.first.beacon.solution"] = "Never replace executable content via translation"
        #expect(throws: (any Error).self) { try translation(unknown).developerPreview(from: data) }
        var empty = completeTexts
        empty["cpp.first.title"] = "  \n"
        #expect(throws: (any Error).self) { try translation(empty).apply(to: data) }
        // Identity texts are a synthetic complete fixture, not a claimed English translation.
        let complete = translation(completeTexts)
        #expect(try complete.coverage(for: data).isComplete)
        #expect(try complete.apply(to: data).exercises.count == 272)
        let course = try Course.bundled()
        let choice = try #require(course.exercises.first { $0.kind == .choice })
        var indistinguishable = completeTexts
        for value in choice.choices {
            indistinguishable[CourseTranslation.valueKey(entityID: choice.id, field: "choice", value: value)] = "The same label"
        }
        #expect(throws: (any Error).self) { try translation(indistinguishable).apply(to: data) }
    }

    @Test func choiceTranslationKeysAreNotBasedOnArrayPositions() throws {
        let course = try Course.bundled()
        let exercise = try #require(course.exercises.first { $0.kind == .choice })
        let labels = Dictionary(uniqueKeysWithValues: exercise.choices.map {
            (CourseTranslation.valueKey(entityID: exercise.id, field: "choice", value: $0), $0)
        })
        for canonical in exercise.choices.reversed() {
            #expect(labels[CourseTranslation.valueKey(entityID: exercise.id, field: "choice", value: canonical)] == canonical)
        }
    }
}
