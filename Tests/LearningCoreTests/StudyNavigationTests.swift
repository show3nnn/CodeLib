import Foundation
import Testing
@testable import LearningCore

struct StudyNavigationTests {
    @Test func searchIncludesSectionsTaskTitlesAndSkills() throws {
        let course = try Course.bundled()
        let progress = ProgressDocument()
        #expect(course.studySections(query: "алгоритмический практикум", status: .all, progress: progress).flatMap(\.lessons).count == 4)
        #expect(course.studySections(query: "Пиковая нагрузка", status: .all, progress: progress).flatMap(\.lessons).map(\.id) == ["cpp.windowlab"])
        #expect(course.studySections(query: "  префиксные   полуинтервалы \n", status: .all, progress: progress).flatMap(\.lessons).map(\.id) == ["cpp.prefixlab"])
        #expect(course.studySections(query: "невозможный-запрос", status: .all, progress: progress).isEmpty)
        #expect(course.studySections(query: " \n", status: .all, progress: progress).flatMap(\.lessons).count == course.lessons.count)
    }

    @Test func filtersDistinguishEmptyDraftVisitedAndCompleted() throws {
        let course = try Course.bundled()
        let lesson = try #require(course.lessons.first)
        let task = try #require(lesson.exercises.first)
        var progress = ProgressDocument()
        #expect(progress.status(of: lesson) == .notStarted)
        progress.lastExerciseID = task.id
        #expect(progress.status(of: lesson) == .inProgress)
        progress.lastExerciseID = nil
        var state = ExerciseProgress()
        state.draft = ""
        progress.exercises[task.id] = state
        #expect(progress.status(of: lesson) == .inProgress)
        #expect(course.studySections(query: "", status: .inProgress, progress: progress).flatMap(\.lessons).map(\.id) == [lesson.id])
        for (index, task) in lesson.exercises.enumerated() {
            var completed = ExerciseProgress()
            completed.completion = index % 2 == 0 ? .automatic : .selfReviewed
            progress.exercises[task.id] = completed
        }
        #expect(progress.status(of: lesson) == .completed)
        #expect(course.studySections(query: "", status: .completed, progress: progress).flatMap(\.lessons).map(\.id) == [lesson.id])
        #expect(course.studySections(query: "", status: .notStarted, progress: progress).flatMap(\.lessons).count == course.lessons.count-1)
    }

    @Test func lessonResumeUsesStableSavedIDThenFirstUnfinished() throws {
        let course = try Course.bundled()
        let lesson = try #require(course.lessons.first)
        var progress = ProgressDocument()
        var state = ExerciseProgress()
        state.completion = .selfReviewed
        progress.exercises[lesson.exercises[0].id] = state
        #expect(progress.resumeExercise(in: lesson)?.id == lesson.exercises[1].id)
        progress.lastExerciseID = lesson.exercises[3].id
        #expect(progress.resumeExercise(in: lesson)?.id == lesson.exercises[3].id)
        progress.lastExerciseID = "unknown.future.id"
        #expect(progress.resumeExercise(in: lesson)?.id == lesson.exercises[1].id)
        for task in lesson.exercises { progress.exercises[task.id] = state }
        #expect(progress.resumeExercise(in: lesson)?.id == lesson.exercises[0].id)
        progress.lessonPositions = [lesson.id: lesson.exercises[2].id, "future.lesson": "future.task"]
        let restored = try ProgressStore.decode(JSONEncoder().encode(progress))
        #expect(restored.resumeExercise(in: lesson)?.id == lesson.exercises[2].id)
        #expect(restored.lessonPositions?["future.lesson"] == "future.task")
        progress.lessonPositions?[lesson.id] = "removed.task"
        #expect(progress.resumeExercise(in: lesson)?.id == lesson.exercises[0].id)
    }

    @Test func newAlgorithmBlockHasPracticeAndValidBoundaries() throws {
        let course = try Course.bundled()
        let block = try #require(course.sections.last)
        #expect(block.id == "cpp.section.algorithm-lab")
        #expect(block.lessons.map(\.id) == ["cpp.prefixlab", "cpp.windowlab", "cpp.pointerslab", "cpp.binarylab"])
        #expect(block.lessons.allSatisfy { $0.exercises.count == 6 })
        #expect(block.lessons.flatMap(\.exercises).filter { $0.kind == .code }.count == 20)
        #expect(course.sections.count == 17 && course.lessons.count == 64 && course.exercises.count == 296)
        try course.validate()
    }
}
