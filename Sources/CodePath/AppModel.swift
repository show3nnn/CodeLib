import AppKit
import LearningCore
import Observation
import SwiftUI

@MainActor @Observable
final class AppModel {
    let course: Course?
    let catalog: CourseCatalog?
    let contentError: AppFailure?
    let appRelease: AppRelease?
    let releaseHistory: ReleaseHistory?
    let releaseHistoryError: AppFailure?
    let dataURL: URL
    private var store: ProgressStore?
    var document = ProgressDocument()
    var storageError: AppFailure?
    var saveError: AppFailure?
    var hasUnsavedChanges = false
    var page: Page = .home {
        didSet { if page != .lesson { execution.cancel() } }
    }
    var selectedExerciseID: String? {
        didSet { if oldValue != selectedExerciseID { execution.cancel() } }
    }
    var message: AppFailure?
    private var updateHistoryPresented = false
    var achievementNotifications: [String] = []
    private var pendingAwards: Set<String> = []
    let execution = CodeExecutionController()

    // Presentation follows committed data, never an in-memory completion from a failed write.
    var startupRoute: StartupRoute {
        let snapshot = document // Observe updates, while routing only from the committed snapshot.
        return StartupRoute.resolve(document: store?.document ?? snapshot, current: appRelease?.version)
    }
    var isExistingLearner: Bool {
        !document.exercises.isEmpty || document.lastStudyDate != nil || document.lastViewedRelease != nil
    }

    func takeUpdateHistoryPresentation() -> Bool {
        guard storageError == nil, startupRoute == .releaseHistory, !updateHistoryPresented else { return false }
        updateHistoryPresented = true
        return true
    }

    @discardableResult
    func saveOnboarding(_ state: OnboardingState, theme: String? = nil, finish: Bool = false) -> Bool {
        guard store != nil else { return false }
        var next = document
        var state = state
        if finish {
            state.completedVersion = 1
            state.draft.id = state.draft.id ?? UUID()
            state.draft.createdAt = state.draft.createdAt ?? Date()
            next.profile = state.draft
            // A fresh installation goes straight to learning, not a simultaneous What's New.
            if !isExistingLearner { next.lastViewedRelease = appRelease?.version }
        }
        next.onboarding = state
        if let theme { next.preferences.theme = theme }
        do { try next.validate() } catch { message = AppFailure(error); return false }
        update { $0 = next }
        return !hasUnsavedChanges && saveError == nil
    }

    @discardableResult
    func saveProfile(_ profile: LocalProfile) -> Bool {
        var profile = profile
        if let existing = document.profile {
            profile.id = existing.id ?? UUID()
            profile.createdAt = existing.createdAt
        } else {
            profile.id = profile.id ?? UUID()
            profile.createdAt = profile.createdAt ?? Date()
        }
        do { try profile.validate() } catch { message = AppFailure(error); return false }
        guard store != nil else { return false }
        update {
            $0.profile = profile
            if $0.onboarding?.completedVersion == 1 { $0.onboarding?.draft = profile }
        }
        return !hasUnsavedChanges && saveError == nil
    }

    enum Page: String, CaseIterable, Identifiable {
        case home, catalog, syllabus, lesson, progress, achievements
        var id: String { rawValue }
        var title: LocalizedStringResource {
            let result: LocalizedStringResource = switch self {
            case .home: "Мои курсы"
            case .catalog: "Каталог"
            case .syllabus: "Программа C++"
            case .lesson: "Обучение"
            case .progress: "Мой прогресс"
            case .achievements: "Достижения"
            }
            return PresentationLocale.resource(result)
        }
        var icon: String {
            switch self {
            case .home: "house"
            case .catalog: "square.grid.2x2"
            case .syllabus: "list.bullet.rectangle"
            case .lesson: "book"
            case .progress: "chart.bar"
            case .achievements: "trophy"
            }
        }
    }

    init() {
        appRelease = try? AppRelease(info: Bundle.main.infoDictionary ?? [:])
        do {
            releaseHistory = try ReleaseHistory.bundled()
            releaseHistoryError = nil
        } catch { releaseHistory = nil; releaseHistoryError = AppFailure(error) }
        do {
            let loaded = try Course.bundled()
            try AchievementCatalog.validate(course: loaded)
            let loadedCatalog = try CourseCatalog.bundled(availableCourseIDs: [loaded.id])
            course = loaded
            catalog = loadedCatalog
            contentError = nil
        } catch { course = nil; catalog = nil; contentError = AppFailure(error) }
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
            if FileManager.default.fileExists(atPath: dataURL.path) { migrateLearningMetadata() }
        } catch {
            store = nil
            storageError = AppFailure(error)
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
        let historical = document.achievements == nil && !document.exercises.isEmpty
        mutate(&document)
        if let course {
            let added = AchievementEngine.reconcile(&document, course: course, now: Date(), historical: historical)
            if !historical { pendingAwards.formUnion(added) }
        }
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
            let earned = AchievementCatalog.all.map(\.id).filter { pendingAwards.contains($0) }
            achievementNotifications.append(contentsOf: earned.filter { !achievementNotifications.contains($0) })
            pendingAwards.removeAll()
        } catch { saveError = AppFailure(error) }
    }

    func updateState(_ id: String, _ mutate: (inout ExerciseProgress) -> Void) {
        let knownExercise = course?.exercises.contains(where: { $0.id == id }) == true
        update {
            var value = $0.exercises[id] ?? ExerciseProgress()
            mutate(&value)
            $0.exercises[id] = value
            $0.lastExerciseID = id
            $0.lastStudyDate = Date()
            if knownExercise {
                if $0.achievements == nil { $0.achievements = AchievementState() }
                $0.achievements?.studyDays.insert(AchievementEngine.dayKey(Date()))
            }
        }
    }

    private func migrateLearningMetadata() {
        var changed = false
        if var profile = document.profile, profile.id == nil {
            profile.id = profile.id ?? UUID()
            // The original creation date is unknown; do not invent one during migration.
            document.profile = profile
            if document.onboarding?.completedVersion == 1 { document.onboarding?.draft = profile }
            changed = true
        }
        if document.achievements == nil, let course {
            _ = AchievementEngine.reconcile(&document, course: course, now: Date(), historical: true)
            changed = true
        }
        if changed { hasUnsavedChanges = true; flush() }
    }

    func open(_ exercise: Exercise) {
        selectedExerciseID = exercise.id
        page = .lesson
        message = nil
        let lessonID = course?.lesson(containing: exercise.id)?.id
        update {
            $0.lastExerciseID = exercise.id
            $0.lastStudyDate = Date()
            if let lessonID {
                var positions = $0.lessonPositions ?? [:]
                positions[lessonID] = exercise.id
                $0.lessonPositions = positions
            }
        }
    }

    func resume() {
        guard let course, let exercise = course.exercises.first(where: { $0.id == document.lastExerciseID })
                ?? course.exercises.first else { return }
        open(exercise)
    }

    func openLesson(_ lesson: Lesson) {
        guard let exercise = document.resumeExercise(in: lesson) else { return }
        open(exercise)
    }

    func resetCodeDraft() {
        guard let exercise, exercise.kind == .code else { return }
        updateState(exercise.id) { $0.draft = exercise.starter }
    }

    func resetTypography() {
        let defaults = Preferences()
        update { $0.preferences.textSize = defaults.textSize; $0.preferences.codeSize = defaults.codeSize }
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

    func runCode(stdin: String) {
        guard let exercise, exercise.kind == .code else { return }
        flush()
        _ = execution.run(exerciseID: exercise.id, source: state(for: exercise.id).draft ?? exercise.starter, stdin: stdin)
        // Running is not grading, completion or an achievement event.
    }

    func exportProgress() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "codelib-progress.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try exportProgress(to: url)
        } catch { message = AppFailure(error, operation: .export) }
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
        guard store != nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importProgress(from: url)
    }

    func importProgress(from source: URL) {
        guard let store else { return }
        do {
            try store.importDocument(from: source)
            document = store.document
            pendingAwards.removeAll()
            achievementNotifications.removeAll()
            hasUnsavedChanges = false
            saveError = nil
            selectedExerciseID = course?.exercises.first { $0.id == document.lastExerciseID }?.id
                ?? course?.exercises.first?.id
            migrateLearningMetadata()
        } catch { message = AppFailure(error, operation: .importProgress) }
    }

    func reset() {
        guard let store else { return }
        do {
            try store.reset()
            document = store.document
            pendingAwards.removeAll()
            achievementNotifications.removeAll()
            hasUnsavedChanges = false
            saveError = nil
            selectedExerciseID = course?.exercises.first?.id
            page = .home
        } catch { message = AppFailure(error, operation: .reset) }
    }

    func restoreBackup() {
        do {
            try ProgressStore.restoreBackup(at: dataURL)
            loadProgress()
        } catch { storageError = AppFailure(error, operation: .restore) }
    }
}
