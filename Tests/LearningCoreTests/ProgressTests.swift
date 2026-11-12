import Foundation
import Testing
import Darwin
@testable import LearningCore

struct ProgressTests {
    func location() throws -> URL {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEPATH_TEST_ROOT"]
                       ?? FileManager.default.currentDirectoryPath + "/.build/test-data")
        let directory = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("progress.json")
    }

    @Test func oldVersionOneFilesGainEditorDefaultsWithoutLosingProgress() throws {
        let url = try location()
        var document = ProgressDocument()
        var state = ExerciseProgress()
        state.draft = "// старый черновик 🚀"
        state.completion = .selfReviewed
        document.exercises["legacy.stable.id"] = state
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as! [String: Any]
        json["preferences"] = ["theme": "dark", "textSize": 20, "codeSize": 18]
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let store = try ProgressStore(url: url)
        #expect(store.document.schemaVersion == 1)
        #expect(store.document.preferences.syntaxHighlighting)
        #expect(store.document.preferences.showLineNumbers)
        #expect(store.document.preferences.theme == "dark")
        #expect(store.document.exercises["legacy.stable.id"]?.draft == state.draft)
        #expect(store.document.completed("legacy.stable.id"))
        try store.update { $0.preferences.syntaxHighlighting = false; $0.preferences.showLineNumbers = false }
        let reopened = try ProgressStore(url: url)
        #expect(!reopened.document.preferences.syntaxHighlighting)
        #expect(!reopened.document.preferences.showLineNumbers)
        #expect(reopened.document.completed("legacy.stable.id"))
    }

    @Test func roundTripPreservesDraftAnswersHintsAndSettings() throws {
        let url = try location()
        let store = try ProgressStore(url: url)
        try store.update {
            var state = ExerciseProgress()
            state.draft = "// Привет\nint main() {}"
            state.answer = "42"
            state.attempts = 2
            state.hintLevel = 2
            state.completion = .selfReviewed
            $0.exercises["stable.task.id"] = state
            $0.lastExerciseID = "stable.task.id"
            $0.lastStudyDate = Date(timeIntervalSince1970: 1000)
            $0.preferences.theme = "dark"
            $0.preferences.codeSize = 20
        }
        let reopened = try ProgressStore(url: url)
        #expect(reopened.document.exercises["stable.task.id"]?.draft == "// Привет\nint main() {}")
        #expect(reopened.document.exercises["stable.task.id"]?.answer == "42")
        #expect(reopened.document.exercises["stable.task.id"]?.attempts == 2)
        #expect(reopened.document.exercises["stable.task.id"]?.hintLevel == 2)
        #expect(reopened.document.completed("stable.task.id"))
        #expect(reopened.document.lastStudyDate == Date(timeIntervalSince1970: 1000))
        #expect(reopened.document.preferences.theme == "dark")
        #expect(reopened.document.preferences.codeSize == 20)
    }

    @Test func backupExportImportReset() throws {
        let url = try location()
        let store = try ProgressStore(url: url)
        try store.update { $0.lastExerciseID = "first" }
        try store.update { $0.lastExerciseID = "second" }
        let backup = try ProgressStore.decode(Data(contentsOf: store.backupURL))
        #expect(backup.lastExerciseID == "first")
        let export = url.appendingPathExtension("export")
        try store.export(to: export)
        try store.reset()
        #expect(store.document.lastExerciseID == nil)
        try store.importDocument(from: export)
        #expect(store.document.lastExerciseID == "second")
    }

    @Test func corruptAndFutureDataAreNeverOverwritten() throws {
        for text in ["broken", "{\"schemaVersion\":99}"] {
            let url = try location()
            let data = Data(text.utf8)
            try data.write(to: url)
            #expect(throws: (any Error).self) { try ProgressStore(url: url) }
            #expect(try Data(contentsOf: url) == data)
        }
    }

    @Test func invalidUpdateDoesNotChangeMemoryOrDisk() throws {
        let url = try location()
        let store = try ProgressStore(url: url)
        try store.update { $0.lastExerciseID = "safe" }
        let bytes = try Data(contentsOf: url)
        #expect(throws: (any Error).self) { try store.update { $0.preferences.textSize = 999 } }
        #expect(store.document.preferences.textSize == 17)
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func concurrentWritersCannotLoseData() throws {
        let url = try location()
        let first = try ProgressStore(url: url)
        let second = try ProgressStore(url: url)
        try first.update { $0.lastExerciseID = "saved" }
        #expect(throws: (any Error).self) { try second.update { $0.lastExerciseID = "lost" } }
        #expect(try ProgressStore(url: url).document.lastExerciseID == "saved")
    }

    @Test func diskFailureDoesNotClaimSuccess() throws {
        let url = try location()
        let blocker = url.deletingLastPathComponent().appendingPathComponent("not-directory")
        try Data("file".utf8).write(to: blocker)
        let store = try ProgressStore(url: blocker.appendingPathComponent("progress.json"))
        #expect(throws: (any Error).self) { try store.update { $0.lastExerciseID = "not saved" } }
        #expect(store.document.lastExerciseID == nil)
    }

    @Test func lockRejectsOverlappingWriterAndAllowsRetry() throws {
        let url = try location()
        let store = try ProgressStore(url: url)
        let fd = open(url.appendingPathExtension("lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        #expect(fd >= 0)
        defer { close(fd) }
        #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
        #expect(throws: (any Error).self) { try store.update { $0.lastExerciseID = "busy" } }
        #expect(store.document.lastExerciseID == nil)
        #expect(flock(fd, LOCK_UN) == 0)
        try store.update { $0.lastExerciseID = "retried" }
        #expect(try ProgressStore(url: url).document.lastExerciseID == "retried")
    }

    @Test func failedImportPreservesCurrentData() throws {
        let url = try location()
        let store = try ProgressStore(url: url)
        try store.update { $0.lastExerciseID = "safe" }
        let original = try Data(contentsOf: url)
        let invalid = url.appendingPathExtension("invalid")
        try Data("{\"schemaVersion\":99}".utf8).write(to: invalid)
        #expect(throws: (any Error).self) { try store.importDocument(from: invalid) }
        #expect(store.document.lastExerciseID == "safe")
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func backupRecoveryUsesLockAndPreservesOriginal() throws {
        let url = try location()
        let store = try ProgressStore(url: url)
        try store.update { $0.lastExerciseID = "backup" }
        try store.update { $0.lastExerciseID = "newer" }
        let backupBytes = try Data(contentsOf: store.backupURL)
        let damaged = Data("damaged progress".utf8)
        try damaged.write(to: url)
        let fd = open(url.appendingPathExtension("lock").path, O_RDWR)
        #expect(fd >= 0)
        defer { close(fd) }
        #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
        #expect(throws: (any Error).self) { try ProgressStore.restoreBackup(at: url) }
        #expect(try Data(contentsOf: url) == damaged)
        #expect(flock(fd, LOCK_UN) == 0)
        let recovered = try ProgressStore.restoreBackup(at: url)
        let original = try #require(recovered)
        #expect(try Data(contentsOf: original) == damaged)
        #expect(try Data(contentsOf: url) == backupBytes)
        #expect(try Data(contentsOf: store.backupURL) == backupBytes)
        #expect(try ProgressStore(url: url).document.lastExerciseID == "backup")
        #expect(throws: (any Error).self) { try store.update { $0.lastExerciseID = "stale" } }
    }

    @Test func invalidBackupCannotReplaceCurrentProgress() throws {
        let url = try location()
        let store = try ProgressStore(url: url)
        try store.update { $0.lastExerciseID = "current" }
        let current = try Data(contentsOf: url)
        try Data("broken".utf8).write(to: store.backupURL)
        #expect(throws: (any Error).self) { try ProgressStore.restoreBackup(at: url) }
        #expect(try Data(contentsOf: url) == current)
    }

    @Test func exportRejectsProtectedPathsAndFileAliases() throws {
        let url = try location()
        let store = try ProgressStore(url: url)
        try store.update { $0.lastExerciseID = "first" }
        try store.update { $0.lastExerciseID = "current" }
        let original = try Data(contentsOf: url)
        let backup = try Data(contentsOf: store.backupURL)
        let symlink = url.deletingLastPathComponent().appendingPathComponent("alias.json")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: url)
        let hardlink = url.deletingLastPathComponent().appendingPathComponent("hardlink.json")
        try FileManager.default.linkItem(at: url, to: hardlink)
        for destination in [url, store.backupURL, url.appendingPathExtension("lock"), symlink, hardlink,
                            url.appendingPathExtension("preserved-test")] {
            #expect(throws: (any Error).self) { try store.export(to: destination) }
        }
        #expect(try Data(contentsOf: url) == original)
        #expect(try Data(contentsOf: store.backupURL) == backup)
        let snapshot = url.deletingLastPathComponent().appendingPathComponent("snapshot.json")
        try store.export(to: snapshot)
        #expect(try ProgressStore.decode(Data(contentsOf: snapshot)).lastExerciseID == "current")
    }

    @Test func editingDoesNotEraseHistoricalCompletionOrUnknownIDs() throws {
        let url = try location()
        let store = try ProgressStore(url: url)
        try store.update {
            var task = ExerciseProgress()
            task.completion = .automatic
            task.answer = "correct"
            $0.exercises["stable.id"] = task
            $0.exercises["future.course.task"] = ExerciseProgress()
        }
        try store.update {
            $0.exercises["stable.id"]?.answer = "new answer"
            $0.exercises["stable.id"]?.lastCorrect = false
        }
        let reopened = try ProgressStore(url: url)
        #expect(reopened.document.completed("stable.id"))
        #expect(reopened.document.exercises["future.course.task"] != nil)
    }
}
