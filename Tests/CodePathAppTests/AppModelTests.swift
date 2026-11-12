import Foundation
import Darwin
import Testing
import LearningCore
@testable import CodePathApp

@Suite(.serialized) @MainActor
struct AppModelTests {
    func setup() throws -> URL {
        let root = ProcessInfo.processInfo.environment["CODEPATH_TEST_ROOT"]
            ?? FileManager.default.currentDirectoryPath + "/.build/test-data"
        let url = URL(fileURLWithPath: root).appendingPathComponent("app-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        setenv("CODEPATH_DATA_DIR", url.path, 1)
        return url
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
