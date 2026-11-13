import Foundation

public enum LessonStatusFilter: String, CaseIterable, Sendable {
    case all, notStarted, inProgress, completed
}

public struct StudySection: Identifiable, Sendable {
    public let section: CourseSection
    public let lessons: [Lesson]
    public var id: String { section.id }
}

extension ProgressDocument {
    public func resumeExercise(in lesson: Lesson) -> Exercise? {
        for candidate in [lessonPositions?[lesson.id], lastExerciseID].compactMap({ $0 }) {
            if let saved = lesson.exercises.first(where: { $0.id == candidate }) { return saved }
        }
        return lesson.exercises.first(where: { !completed($0.id) }) ?? lesson.exercises.first
    }

    public func status(of lesson: Lesson) -> LessonStatusFilter {
        if lessonCompleted(lesson) { return .completed }
        let started = lesson.exercises.contains { task in
            if task.id == lastExerciseID || task.id == lessonPositions?[lesson.id] { return true }
            guard let state = exercises[task.id] else { return false }
            return state.draft != nil || !state.answer.isEmpty || state.attempts > 0 || state.hintLevel > 0 || state.completion != .unfinished
        }
        return started ? .inProgress : .notStarted
    }
}

extension Course {
    public func studySections(query: String, status: LessonStatusFilter, progress: ProgressDocument) -> [StudySection] {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return sections.compactMap { section in
            let matches = section.lessons.filter { lesson in
                guard status == .all || progress.status(of: lesson) == status else { return false }
                let searchable = ([section.title, section.summary, lesson.title, lesson.summary]
                    + lesson.exercises.map(\.title) + lesson.exercises.flatMap(\.skills)).joined(separator: "\n")
                return terms.allSatisfy { searchable.localizedCaseInsensitiveContains($0) }
            }
            return matches.isEmpty ? nil : StudySection(section: section, lessons: matches)
        }
    }
}
