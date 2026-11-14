import Foundation
import Darwin
import Testing
import LearningCore
@testable import CodePathApp

@Suite(.serialized) @MainActor
struct AppModelTests {
    @Test func executionRejectionNeverGradesOrMutatesProgress() throws {
        _ = try setup()
        let model = AppModel()
        let first = try #require(model.course?.exercises.first(where: { $0.kind == .code }))
        model.open(first)
        model.updateState(first.id) { $0.draft = String(repeating: "x", count: 65_537) }
        let before = try Data(contentsOf: model.dataURL)
        model.runCode(stdin: "")
        #expect(model.execution.failure == .invalidRequest)
        #expect(!model.execution.isBusy)
        #expect(model.state(for: first.id).completion == .unfinished)
        #expect(try Data(contentsOf: model.dataURL) == before)
        model.updateState(first.id) { $0.draft = "int main(){}" }
        let input = String(repeating: "👩🏽‍💻", count: 5000)
        model.execution.inputs[first.id] = input
        let beforeInput = try Data(contentsOf: model.dataURL)
        model.runCode(stdin: input)
        #expect(model.execution.failure == .invalidRequest)
        #expect(model.execution.inputs[first.id] == input)
        #expect(try Data(contentsOf: model.dataURL) == beforeInput)
    }

    @Test func gradingPersistsOnlyCompleteRuntimeOutcomes() throws {
        _ = try setup()
        let model = AppModel()
        let task = try #require(model.course?.exercises.first { $0.gradingFixtures != nil })
        model.open(task)
        #expect(model.state(for: task.id).attempts == 0)
        model.recordGrading(exerciseID: task.id, passed: false)
        #expect(model.state(for: task.id).attempts == 1)
        #expect(model.state(for: task.id).lastCorrect == false)
        #expect(model.state(for: task.id).completion == .unfinished)
        model.recordGrading(exerciseID: task.id, passed: true)
        #expect(model.state(for: task.id).attempts == 2)
        #expect(model.state(for: task.id).lastCorrect == true)
        #expect(model.state(for: task.id).completion == .automatic)
        model.selfComplete()
        #expect(model.state(for: task.id).completion == .automatic)
        model.recordGrading(exerciseID: task.id, passed: false)
        #expect(model.state(for: task.id).completion == .automatic)
        #expect(model.state(for: task.id).attempts == 3)
        model.recordGrading(exerciseID: "future.unknown", passed: true)
        #expect(model.state(for: "future.unknown").attempts == 0)

        let restored = AppModel()
        #expect(restored.state(for: task.id).attempts == 3)
        #expect(restored.state(for: task.id).lastCorrect == false)
        #expect(restored.state(for: task.id).completion == .automatic)
    }

    @Test func compilerBytePositionsConvertToUTF16WithoutChangingSource() {
        let source = "// 👩🏽‍💻\nint привет = 1; missing;\n"
        let bytesBefore = "int привет = 1; ".utf8.count
        let navigation = EditorNavigation(source: source, line: 2, byteColumn: bytesBefore + 1)
        #expect(navigation.range?.location == (source as NSString).range(of: "missing").location)
        #expect(navigation.range?.length == 1)
        #expect(EditorNavigation(source: source, line: 999, byteColumn: 1).range == nil)
        #expect(EditorNavigation(source: source, line: 0, byteColumn: 1).range == nil)
        #expect(navigation.source == source)
    }

    func setup() throws -> URL {
        let root = ProcessInfo.processInfo.environment["CODEPATH_TEST_ROOT"]
            ?? FileManager.default.currentDirectoryPath + "/.build/test-data"
        let url = URL(fileURLWithPath: root).appendingPathComponent("app-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        setenv("CODEPATH_DATA_DIR", url.path, 1)
        return url
    }

    @Test func importAndResetFailuresKeepTypedReasonsAndPersistedState() throws {
        let root = try setup()
        let model = AppModel()
        model.update { $0.exercises["future.id"] = ExerciseProgress(); $0.lastExerciseID = "future.id" }
        let before = try Data(contentsOf: model.dataURL)
        let input = root.appendingPathComponent("future-schema.json")
        try Data("{\"schemaVersion\":99}".utf8).write(to: input)
        model.importProgress(from: input)
        #expect(model.message?.operation == .importProgress)
        #expect(model.message?.cause as? StorageError == .unsupportedVersion(99))
        #expect(try Data(contentsOf: model.dataURL) == before)
        #expect(model.document.exercises["future.id"] != nil)
        model.message = nil
        let descriptor = open(model.dataURL.appendingPathExtension("lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        #expect(descriptor >= 0)
        defer { flock(descriptor, LOCK_UN); close(descriptor) }
        #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        model.reset()
        #expect(model.message?.operation == .reset)
        #expect(model.message?.cause as? StorageError == .locked)
        #expect(try Data(contentsOf: model.dataURL) == before)
        #expect(model.document.exercises["future.id"] != nil)
    }

    @Test func releaseAcknowledgementRetriesFailedWritesAndPersists() throws {
        let root = try setup()
        let model = AppModel()
        let version = try #require(model.releaseHistory?.releases.first?.version)
        let lock = root.appendingPathComponent("progress.json.lock")
        let descriptor = open(lock.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        #expect(descriptor >= 0)
        defer { flock(descriptor, LOCK_UN); close(descriptor) }
        #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        #expect(!model.markReleaseViewed(version))
        #expect(model.saveError != nil)
        #expect(!model.markReleaseViewed(version))
        #expect(AppModel().document.lastViewedRelease == nil)
        #expect(flock(descriptor, LOCK_UN) == 0)
        #expect(model.markReleaseViewed(version))
        #expect(model.saveError == nil)
        #expect(AppModel().document.lastViewedRelease == version)
        let old = try #require(model.releaseHistory?.releases.last?.version)
        #expect(model.markReleaseViewed(old))
        #expect(model.document.lastViewedRelease == version)
    }

    @Test func brokenStorageCannotAcknowledgeRelease() throws {
        let root = try setup()
        try Data("broken".utf8).write(to: root.appendingPathComponent("progress.json"))
        let model = AppModel()
        let version = try #require(model.releaseHistory?.releases.first?.version)
        #expect(!model.markReleaseViewed(version))
        #expect(model.document.lastViewedRelease == nil)
    }

    @Test func setupCompletionWaitsForDiskAndKeepsLegacyProgress() throws {
        let root = try setup()
        let model = AppModel()
        model.updateState("unknown.task") { $0.draft = ""; $0.completion = .selfReviewed }
        var state = OnboardingState()
        state.step = .appearance
        state.draft = LocalProfile(nickname: "Анна", avatar: .star)
        #expect(model.saveOnboarding(state))
        #expect(AppModel().document.onboarding?.step == .appearance)
        let descriptor = open(root.appendingPathComponent("progress.json.lock").path, O_RDWR)
        #expect(descriptor >= 0)
        defer { flock(descriptor, LOCK_UN); close(descriptor) }
        #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        #expect(!model.saveOnboarding(state, finish: true))
        #expect(model.startupRoute == .onboarding)
        #expect(AppModel().document.profile == nil)
        #expect(flock(descriptor, LOCK_UN) == 0)
        #expect(model.saveOnboarding(state, theme: "dark", finish: true))
        let reopened = AppModel()
        #expect(reopened.document.profile?.nickname == "Анна")
        #expect(reopened.document.preferences.theme == "dark")
        #expect(reopened.document.exercises["unknown.task"]?.draft == "")
        #expect(reopened.document.completed("unknown.task"))
        #expect(reopened.document.lastViewedRelease == nil)
        #expect(reopened.saveProfile(LocalProfile(nickname: "Новое имя", avatar: .leaf)))
        #expect(AppModel().document.onboarding?.draft.nickname == "Новое имя")
    }

    @Test func invalidProfileNeverReplacesValidProgress() throws {
        _ = try setup()
        let model = AppModel()
        #expect(model.saveProfile(LocalProfile(nickname: "Имя")))
        #expect(!model.saveProfile(LocalProfile(nickname: "  ")))
        #expect(AppModel().document.profile?.nickname == "Имя")
    }

    @Test func openingLessonKeepsItsSavedTaskAcrossRelaunch() throws {
        _ = try setup()
        let model = AppModel()
        let lesson = try #require(model.course?.lessons.first)
        model.open(lesson.exercises[2])
        let other = try #require(model.course?.lessons.dropFirst().first)
        model.open(other.exercises[1])
        let reopened = AppModel()
        reopened.openLesson(lesson)
        #expect(reopened.exercise?.id == lesson.exercises[2].id)
        #expect(reopened.document.lastExerciseID == lesson.exercises[2].id)
    }

    @Test func achievementsNotifyOnlyAfterSuccessfulWriteAndNeverRepeat() throws {
        let root = try setup()
        let model = AppModel()
        let task = try #require(model.course?.exercises.first { $0.kind == .code })
        model.open(task)
        let descriptor = open(root.appendingPathComponent("progress.json.lock").path, O_RDWR)
        #expect(descriptor >= 0)
        defer { flock(descriptor, LOCK_UN); close(descriptor) }
        #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        model.selfComplete()
        #expect(model.hasUnsavedChanges && model.achievementNotifications.isEmpty)
        #expect(AppModel().document.achievements?.awards["award.selfreview"] == nil)
        #expect(flock(descriptor, LOCK_UN) == 0)
        model.flush()
        #expect(model.achievementNotifications == ["award.selfreview"])
        model.achievementNotifications.removeAll()
        model.selfComplete()
        #expect(model.achievementNotifications.isEmpty)
        #expect(AppModel().document.achievements?.awards["award.selfreview"] != nil)
        #expect(AppModel().achievementNotifications.isEmpty)
    }

    @Test func oldProgressBackfillsSilentlyAndLegacyProfileGetsStableUUID() throws {
        let root = try setup()
        let course = try Course.bundled()
        let url = root.appendingPathComponent("progress.json")
        var document = ProgressDocument()
        var profile = LocalProfile(nickname: "Прежний профиль")
        profile.id = nil; profile.createdAt = nil
        document.profile = profile
        for task in course.exercises.prefix(60) {
            var state = ExerciseProgress(); state.completion = .selfReviewed
            document.exercises[task.id] = state
        }
        try JSONEncoder().encode(document).write(to: url)
        let model = AppModel()
        #expect(model.achievementNotifications.isEmpty)
        #expect((model.document.achievements?.awards.count ?? 0) > 5)
        #expect(model.document.achievements?.awards.values.allSatisfy(\.historical) == true)
        let id = try #require(model.document.profile?.id)
        #expect(AppModel().document.profile?.id == id)
        #expect(model.document.profile?.createdAt == nil)
        #expect(model.saveProfile(LocalProfile(nickname: "Новое имя")))
        #expect(AppModel().document.profile?.id == id)
    }

    @Test func codeAndTypographyResetsKeepLearningHistoryAndOtherPreferences() throws {
        _ = try setup()
        let model = AppModel()
        let task = try #require(model.course?.exercises.first { $0.kind == .code })
        model.open(task)
        model.updateState(task.id) { $0.draft = ""; $0.hintLevel = 2; $0.completion = .selfReviewed }
        model.update { $0.preferences.textSize = 28; $0.preferences.codeSize = 26; $0.preferences.theme = "dark"; $0.preferences.achievementSounds = false }
        model.resetCodeDraft()
        model.resetTypography()
        let restored = AppModel()
        #expect(restored.state(for: task.id).draft == task.starter)
        #expect(restored.state(for: task.id).completion == .selfReviewed && restored.state(for: task.id).hintLevel == 2)
        #expect(restored.document.preferences.textSize == Preferences().textSize)
        #expect(restored.document.preferences.codeSize == Preferences().codeSize)
        #expect(restored.document.preferences.theme == "dark" && !restored.document.preferences.achievementSounds)
    }

    @Test func codeIsNeverAutomaticallyChecked() throws {
        _ = try setup()
        let model = AppModel()
        let task = try #require(model.course?.exercises.first { $0.kind == .code })
        model.open(task)
        model.updateState(task.id) { $0.draft = task.solution; $0.answer = task.solution }
        model.check()
        #expect(model.state(for: task.id).completion == .unfinished)
        #expect(model.state(for: task.id).attempts == 0)
        model.selfComplete()
        #expect(model.state(for: task.id).completion == .selfReviewed)
        #expect(!model.hasUnsavedChanges)
    }

    @Test func automaticCheckingAndEditingPreserveHistoricalProgress() throws {
        _ = try setup()
        let model = AppModel()
        let task = try #require(model.course?.exercises.first { $0.kind == .choice })
        model.open(task)
        model.updateState(task.id) { $0.answer = "wrong" }
        model.check()
        #expect(model.state(for: task.id).lastCorrect == false)
        #expect(model.state(for: task.id).completion == .unfinished)
        model.updateState(task.id) { $0.answer = task.answer! }
        model.check()
        #expect(model.state(for: task.id).attempts == 2)
        #expect(model.state(for: task.id).completion == .automatic)
        model.updateState(task.id) { $0.answer = "edited"; $0.lastCorrect = nil }
        #expect(model.document.completed(task.id))
        let reopened = AppModel()
        #expect(reopened.state(for: task.id).answer == "edited")
        #expect(reopened.state(for: task.id).completion == .automatic)
    }

    @Test func failedWriteIsVisibleRetainsDraftAndCanRetry() throws {
        let root = try setup()
        let blocker = root.appendingPathComponent("blocker")
        try Data("file".utf8).write(to: blocker)
        setenv("CODEPATH_DATA_DIR", blocker.path, 1)
        let model = AppModel()
        let task = try #require(model.course?.exercises.first)
        model.updateState(task.id) { $0.draft = "unsaved draft" }
        #expect(model.hasUnsavedChanges)
        #expect(model.saveError != nil)
        #expect(model.state(for: task.id).draft == "unsaved draft")
        try FileManager.default.removeItem(at: blocker) // This test's own single-file fixture.
        model.flush()
        #expect(!model.hasUnsavedChanges)
        #expect(model.saveError == nil)
        let disk = try ProgressStore(url: model.dataURL)
        #expect(disk.document.exercises[task.id]?.draft == "unsaved draft")
    }

    @Test func brokenProgressIsNotSilentlyResetAndBackupCanBeRestored() throws {
        let root = try setup()
        let url = root.appendingPathComponent("progress.json")
        let store = try ProgressStore(url: url)
        try store.update { $0.lastExerciseID = "stable" }
        try store.update { $0.lastExerciseID = "later" }
        try Data("damaged".utf8).write(to: url)
        let model = AppModel()
        #expect(model.storageError != nil)
        model.update { $0.lastExerciseID = "must not overwrite" }
        #expect(try String(contentsOf: url, encoding: .utf8) == "damaged")
        model.restoreBackup()
        #expect(model.storageError == nil)
        #expect(model.document.lastExerciseID == "stable")
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        let preserved = try #require(files.first { $0.hasPrefix("progress.json.preserved-") })
        #expect(try String(contentsOf: root.appendingPathComponent(preserved), encoding: .utf8) == "damaged")
    }

    @Test func resumeFallbackAndNavigationStayInsideCourse() throws {
        _ = try setup()
        let model = AppModel()
        let course = try #require(model.course)
        let first = try #require(course.exercises.first)
        let last = try #require(course.exercises.last)
        model.update { $0.lastExerciseID = "removed" }
        model.resume()
        #expect(model.exercise?.id == first.id)
        model.move(-1)
        #expect(model.exercise?.id == first.id)
        model.open(last)
        model.move(1)
        #expect(model.exercise?.id == last.id)
        let restored = AppModel()
        restored.resume()
        #expect(restored.exercise?.id == last.id)
    }

    @Test func emptyDraftIsNotReplacedWithStarterAndResetIsDurable() throws {
        _ = try setup()
        let model = AppModel()
        let task = try #require(model.course?.exercises.first)
        model.open(task)
        model.updateState(task.id) { $0.draft = "" }
        #expect(AppModel().state(for: task.id).draft == "")
        model.reset()
        let reopened = AppModel()
        #expect(reopened.document.exercises.isEmpty)
        #expect(reopened.document.lastExerciseID == nil)
    }

    @Test func exportKeepsUnsavedDraftWithoutOverwritingStore() throws {
        let root = try setup()
        let model = AppModel()
        let task = try #require(model.course?.exercises.first)
        model.open(task)
        let original = try Data(contentsOf: model.dataURL)
        let fd = open(model.dataURL.appendingPathExtension("lock").path, O_RDWR)
        #expect(fd >= 0)
        defer { flock(fd, LOCK_UN); close(fd) }
        #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
        model.updateState(task.id) { $0.draft = "unsaved export" }
        #expect(model.hasUnsavedChanges)
        #expect(throws: (any Error).self) { try model.exportProgress(to: model.dataURL) }
        let snapshot = root.appendingPathComponent("export.json")
        try model.exportProgress(to: snapshot)
        #expect(try ProgressStore.decode(Data(contentsOf: snapshot)).exercises[task.id]?.draft == "unsaved export")
        #expect(try Data(contentsOf: model.dataURL) == original)
        #expect(model.hasUnsavedChanges)
    }

    @Test func importedMaximumAttemptCounterCannotOverflow() throws {
        _ = try setup()
        let model = AppModel()
        let task = try #require(model.course?.exercises.first { $0.kind == .choice })
        model.open(task)
        model.updateState(task.id) { $0.attempts = Int.max; $0.answer = task.answer! }
        model.check()
        #expect(model.state(for: task.id).attempts == Int.max)
        #expect(model.state(for: task.id).completion == .automatic)
    }
}
