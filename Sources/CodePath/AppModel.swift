import AppKit
import LearningCore
import Observation
import SwiftUI

@MainActor @Observable
final class AppModel {
    let course: Course?
    let catalog: CourseCatalog?
    let contentError: String?
    let appRelease: AppRelease?
    let releaseHistory: ReleaseHistory?
    let releaseHistoryError: String?
    let dataURL: URL
    private var store: ProgressStore?
    var document = ProgressDocument()
    var storageError: String?
    var saveError: String?
    var hasUnsavedChanges = false
    var page: Page = .home
    var selectedExerciseID: String?
    var message: String?

    enum Page: String, CaseIterable, Identifiable {
        case home, catalog, syllabus, lesson, progress
        var id: String { rawValue }
        var title: String {
            switch self {
            case .home: "Мои курсы"
            case .catalog: "Каталог"
            case .syllabus: "Программа C++"
            case .lesson: "Обучение"
            case .progress: "Мой прогресс"
            }
        }
        var icon: String {
            switch self {
            case .home: "house"
            case .catalog: "square.grid.2x2"
            case .syllabus: "list.bullet.rectangle"
            case .lesson: "book"
            case .progress: "chart.bar"
            }
        }
    }

    init() {
        appRelease = try? AppRelease(info: Bundle.main.infoDictionary ?? [:])
        do {
            releaseHistory = try ReleaseHistory.bundled()
            releaseHistoryError = nil
        } catch { releaseHistory = nil; releaseHistoryError = error.localizedDescription }
        do {
            let loaded = try Course.bundled()
            let loadedCatalog = try CourseCatalog.bundled(availableCourseIDs: [loaded.id])
            course = loaded
            catalog = loadedCatalog
            contentError = nil
        } catch { course = nil; catalog = nil; contentError = error.localizedDescription }
        if let path = ProcessInfo.processInfo.environment["CODEPATH_DATA_DIR"] {
            dataURL = URL(fileURLWithPath: path).appendingPathComponent("progress.json")
        } else {
            dataURL = URL.applicationSupportDirectory.appendingPathComponent("CodePath", isDirectory: true)
                .appendingPathComponent("progress.json")
        }
        loadProgress()
    }

    private func loadProgress() {
        do {
            let store = try ProgressStore(url: dataURL)
            self.store = store
            document = store.document
            selectedExerciseID = course?.exercises.first { $0.id == document.lastExerciseID }?.id
                ?? course?.exercises.first?.id
            storageError = nil
        } catch {
            store = nil
            storageError = error.localizedDescription
        }
    }

    var exercise: Exercise? { course?.exercises.first { $0.id == selectedExerciseID } }
    var lesson: Lesson? { course?.lesson(containing: selectedExerciseID) }
    var colorScheme: ColorScheme? {
        switch document.preferences.theme { case "light": .light; case "dark": .dark; default: nil }
    }
    var fraction: Double {
        guard let course, !course.exercises.isEmpty else { return 0 }
        return Double(document.completedCount(in: course)) / Double(course.exercises.count)
    }

    func state(for id: String) -> ExerciseProgress { document.exercises[id] ?? ExerciseProgress() }

    func update(_ mutate: (inout ProgressDocument) -> Void) {
        guard store != nil else { return }
        mutate(&document)
        hasUnsavedChanges = true
        flush()
    }

    func flush() {
        guard hasUnsavedChanges, let store else { return }
        do {
            let snapshot = document
            try store.update { $0 = snapshot }
            hasUnsavedChanges = false
            saveError = nil
        } catch { saveError = error.localizedDescription }
    }

    func updateState(_ id: String, _ mutate: (inout ExerciseProgress) -> Void) {
        update {
            var value = $0.exercises[id] ?? ExerciseProgress()
            mutate(&value)
            $0.exercises[id] = value
            $0.lastExerciseID = id
            $0.lastStudyDate = Date()
        }
    }

    func open(_ exercise: Exercise) {
        selectedExerciseID = exercise.id
        page = .lesson
        message = nil
        update { $0.lastExerciseID = exercise.id; $0.lastStudyDate = Date() }
    }

    func resume() {
        guard let course, let exercise = course.exercises.first(where: { $0.id == document.lastExerciseID })
                ?? course.exercises.first else { return }
        open(exercise)
    }

    func move(_ offset: Int) {
        guard let id = selectedExerciseID, let next = course?.adjacent(to: id, offset: offset) else { return }
        open(next)
    }

    func check() {
        guard let exercise else { return }
        let state = state(for: exercise.id)
        guard let correct = AnswerChecker.check(state.answer, for: exercise) else { return }
        updateState(exercise.id) {
            if $0.attempts < Int.max { $0.attempts += 1 }
            $0.lastCorrect = correct
            if correct { $0.completion = .automatic }
        }
    }

    func selfComplete() {
        guard let exercise, exercise.kind == .code else { return }
        updateState(exercise.id) { $0.completion = .selfReviewed }
    }

    func exportProgress() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "codelib-progress.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try exportProgress(to: url)
        } catch { message = "Не удалось экспортировать: \(error.localizedDescription)" }
    }

    func exportProgress(to destination: URL) throws {
        try ProgressStore.export(document, to: destination, protecting: dataURL)
    }

    @discardableResult
    func markReleaseViewed(_ version: NumericVersion) -> Bool {
        guard store != nil, releaseHistory?.releases.contains(where: { $0.version == version }) == true else { return false }
        if let seen = document.lastViewedRelease, seen >= version {
            flush()
        } else {
            update { $0.lastViewedRelease = version }
        }
        return !hasUnsavedChanges && storageError == nil && saveError == nil
    }

    func importProgress() {
        guard let store else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.importDocument(from: url)
            document = store.document
            hasUnsavedChanges = false
            saveError = nil
            selectedExerciseID = course?.exercises.first { $0.id == document.lastExerciseID }?.id
                ?? course?.exercises.first?.id
        } catch { message = "Импорт отменён, текущие данные сохранены: \(error.localizedDescription)" }
    }

    func reset() {
        guard let store else { return }
        do {
            try store.reset()
            document = store.document
            hasUnsavedChanges = false
            saveError = nil
            selectedExerciseID = course?.exercises.first?.id
            page = .home
        } catch { message = "Сброс не выполнен: \(error.localizedDescription)" }
    }

    func restoreBackup() {
        do {
            try ProgressStore.restoreBackup(at: dataURL)
            loadProgress()
        } catch { storageError = "Восстановление не выполнено: \(error.localizedDescription)" }
    }
}
