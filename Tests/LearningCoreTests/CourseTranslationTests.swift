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
        #expect(report.translated == 2904 && report.translated == report.total)
        #expect(report.unknown.isEmpty && report.missing.isEmpty && report.isComplete)
        #expect(translation.status == .draft)
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

    @Test func entireCourseHasNoUntranslatedPresentationFields() throws {
        let data = try source()
        let course = try JSONDecoder().decode(Course.self, from: data)
        let expected = Set(CourseTranslation.sourceTexts(in: course).keys)
        let translation = try draft()
        #expect(Set(translation.texts.keys) == expected)
        #expect(translation.texts.count == 2904)
        let preview = try translation.developerPreview(from: data)
        #expect(preview.lessons.first(where: { $0.id == "cpp.tickets" })?.title == "Mini-project: ticket office")
        #expect(preview.lessons.first(where: { $0.id == "cpp.telemetry" })?.title == "Assessment: telemetry")
        #expect(preview.lessons.first(where: { $0.id == "cpp.mission" })?.title == "Mini-project: route analyzer")
        #expect(preview.lessons.first(where: { $0.id == "cpp.getline" })?.title == "A whole line")
        #expect(preview.lessons.first(where: { $0.id == "cpp.inventory" })?.title == "Mini-project: inventory")
        #expect(preview.lessons.first(where: { $0.id == "cpp.tournament" })?.title == "Mini-project: tournament")
        #expect(preview.lessons.first(where: { $0.id == "cpp.lifetime" })?.title == "Lifetime and bounds")
        #expect(preview.lessons.first(where: { $0.id == "cpp.raii" })?.title == "unique_ptr and automatic release")
        #expect(preview.lessons.first(where: { $0.id == "cpp.encapsulation" })?.title == "Mini-project: a store of records")
        #expect(preview.lessons.first(where: { $0.id == "cpp.undefined" })?.title == "Undefined behavior")
        #expect(preview.lessons.first(where: { $0.id == "cpp.files" })?.title == "File streams")
        #expect(preview.lessons.first(where: { $0.id == "cpp.console" })?.title == "Project: command panel")
        #expect(preview.lessons.first(where: { $0.id == "cpp.capstone" })?.title == "Capstone: supplies dispatcher")
        #expect(preview.lessons.first(where: { $0.id == "cpp.binarylab" })?.title == "Binary search and searching the answer")
        for exercise in preview.exercises where exercise.kind == .choice {
            #expect(AnswerChecker.check(exercise.answer!, for: exercise) == true)
            #expect(exercise.choices.allSatisfy { exercise.choiceLabels?[$0] != nil })
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

    @Test func allAutomaticAnswersAndProfileSurvivePreviewRoundTrip() throws {
        let data = try source()
        let base = try JSONDecoder().decode(Course.self, from: data)
        let preview = try draft().developerPreview(from: data)
        let automatic = base.exercises.filter { $0.kind == .choice || $0.kind == .output }
        #expect(automatic.count == 97)
        let folder = root.appendingPathComponent(".build/test-data/locale-roundtrip-\(UUID().uuidString)")
        let store = try ProgressStore(url: folder.appendingPathComponent("progress.json"))
        let profile = LocalProfile(nickname: "Пилот 👩🏽‍💻", avatar: .star)
        let recognizedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try store.update { document in
            document.profile = profile
            document.lastExerciseID = "cpp.inventory.compress"
            document.lessonPositions = ["cpp.getline": "cpp.getline.space", "cpp.inventory": "cpp.inventory.compress", "future.lesson": "future.task"]
            document.preferences.codeSize = 22
            var awards = AchievementState()
            awards.awards["award.checked"] = AchievementAward(recognizedAt: recognizedAt, historical: true)
            awards.awards["future.award"] = AchievementAward(recognizedAt: recognizedAt, historical: false)
            document.achievements = awards
            for exercise in automatic {
                var progress = ExerciseProgress()
                progress.answer = exercise.answer!
                progress.completion = .automatic
                progress.attempts = 1
                document.exercises[exercise.id] = progress
            }
            var code = ExerciseProgress()
            code.draft = "// Мой черновик\nstd::cout << 42;"
            code.completion = .selfReviewed
            code.hintLevel = 2
            document.exercises["cpp.inventory.compress"] = code
            var empty = ExerciseProgress()
            empty.draft = ""
            document.exercises["cpp.functions.square"] = empty
            document.exercises["future.task"] = ExerciseProgress()
        }
        let savedBytes = try Data(contentsOf: store.url)
        let reopened = try ProgressStore(url: store.url).document
        for course in [preview, base, preview] {
            for exercise in automatic {
                let projected = try #require(course.exercises.first { $0.id == exercise.id })
                let savedAnswer = try #require(reopened.exercises[exercise.id]?.answer)
                #expect(AnswerChecker.check(savedAnswer, for: projected) == true)
            }
            #expect(reopened.completedCount(in: course) == 98)
            #expect(reopened.lastExerciseID.flatMap { id in course.exercises.first { $0.id == id } }?.id == "cpp.inventory.compress")
        }
        #expect(reopened.profile == profile)
        #expect(reopened.preferences.codeSize == 22)
        #expect(reopened.lessonPositions == store.document.lessonPositions)
        #expect(reopened.achievements?.awards["award.checked"]?.recognizedAt == recognizedAt)
        #expect(reopened.achievements?.awards["award.checked"]?.historical == true)
        #expect(reopened.achievements?.awards["future.award"] != nil)
        #expect(reopened.exercises["cpp.inventory.compress"]?.draft == "// Мой черновик\nstd::cout << 42;")
        #expect(reopened.exercises["cpp.inventory.compress"]?.completion == .selfReviewed)
        #expect(reopened.exercises["cpp.inventory.compress"]?.hintLevel == 2)
        #expect(reopened.exercises["cpp.functions.square"]?.draft == "")
        #expect(reopened.exercises["future.task"] != nil)
        #expect(try Data(contentsOf: store.url) == savedBytes)
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
        var missing = draft.texts
        missing.removeValue(forKey: "cpp.binarylab.capacity.prompt")
        let incomplete = translation(missing)
        #expect(try incomplete.coverage(for: data).missing == ["cpp.binarylab.capacity.prompt"])
        #expect(throws: (any Error).self) { try incomplete.apply(to: data) }
        var unknown = draft.texts
        unknown["cpp.first.beacon.solution"] = "Never replace executable content via translation"
        #expect(throws: (any Error).self) { try translation(unknown).developerPreview(from: data) }
        var empty = completeTexts
        empty["cpp.first.title"] = "  \n"
        #expect(throws: (any Error).self) { try translation(empty).apply(to: data) }
        // Identity texts are a synthetic complete fixture, not a claimed English translation.
        let complete = translation(completeTexts)
        #expect(try complete.coverage(for: data).isComplete)
        #expect(try complete.apply(to: data).exercises.count == Course.bundled().exercises.count)
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
