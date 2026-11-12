import Foundation
import Testing
@testable import LearningCore

struct ContentTests {
    @Test func catalogHasOnlyRealAvailableContentAndDisabledFutureCourses() throws {
        let course = try Course.bundled()
        let catalog = try CourseCatalog.bundled(availableCourseIDs: [course.id])
        #expect(catalog.entries.filter { $0.availability == .available }.map(\.id) == [course.id])
        #expect(catalog.entries.filter { $0.availability == .comingSoon }.count == 4)
        #expect(throws: (any Error).self) { try catalog.validate(availableCourseIDs: []) }
    }
    @Test func bundledContentIsValidAndCodePredominates() throws {
        let course = try Course.bundled()
        try course.validate()
        #expect(course.exercises.filter { $0.kind == .code }.count > course.exercises.count / 2)
        #expect(course.lessons.allSatisfy { !$0.recap.isEmpty && $0.minutes > 0 })
        for exercise in course.exercises where exercise.kind != .code {
            #expect(AnswerChecker.check(exercise.answer!, for: exercise) == true)
            #expect(AnswerChecker.check("definitely wrong", for: exercise) == false)
        }
    }

    @Test func codeCannotBeAutomaticallyGraded() throws {
        let exercise = try #require(Course.bundled().exercises.first { $0.kind == .code })
        #expect(AnswerChecker.check(exercise.solution, for: exercise) == nil)
    }

    @Test func outputKeepsSignificantWhitespace() throws {
        let exercise = try #require(Course.bundled().exercises.first { $0.kind == .output })
        let answer = try #require(exercise.answer)
        #expect(AnswerChecker.check(answer + "\n", for: exercise) == true)
        #expect(AnswerChecker.check(answer + " ", for: exercise) == false)
        #expect(AnswerChecker.check(answer + "\n\n", for: exercise) == false)
    }

    @Test func navigationBoundariesAndRelationships() throws {
        let course = try Course.bundled()
        let first = try #require(course.exercises.first)
        let last = try #require(course.exercises.last)
        #expect(course.adjacent(to: first.id, offset: -1) == nil)
        #expect(course.adjacent(to: last.id, offset: 1) == nil)
        #expect(course.adjacent(to: "missing", offset: 1) == nil)
        #expect(course.adjacent(to: last.id, offset: Int.max) == nil)
        #expect(course.adjacent(to: first.id, offset: Int.min) == nil)
        for (index, task) in course.exercises.enumerated() {
            #expect(course.lesson(containing: task.id) != nil)
            if index > 0 { #expect(course.adjacent(to: task.id, offset: -1)?.id == course.exercises[index - 1].id) }
            if index + 1 < course.exercises.count { #expect(course.adjacent(to: task.id, offset: 1)?.id == course.exercises[index + 1].id) }
        }
    }

    @Test func statisticsUseStableIDsAndIgnoreRemovedContent() throws {
        let course = try Course.bundled()
        let lesson = try #require(course.lessons.first)
        var document = ProgressDocument()
        for task in lesson.exercises {
            var state = ExerciseProgress()
            state.completion = .selfReviewed
            document.exercises[task.id] = state
        }
        document.exercises["removed.id"] = document.exercises[lesson.exercises[0].id]
        #expect(document.completedCount(in: course) == lesson.exercises.count)
        #expect(document.lessonCompleted(lesson))
        let reversed = try JSONSerialization.jsonObject(with: JSONEncoder().encode(course)) as! [String: Any]
        var changed = reversed
        changed["sections"] = (reversed["sections"] as! [Any]).reversed().map { $0 }
        let reordered = try JSONDecoder().decode(Course.self, from: JSONSerialization.data(withJSONObject: changed))
        #expect(document.completedCount(in: reordered) == lesson.exercises.count)
    }

    @Test func validatorRejectsDuplicateIDsAndBrokenDependencies() throws {
        let course = try Course.bundled()
        let bytes = try JSONEncoder().encode(course)
        var object = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        var sections = object["sections"] as! [[String: Any]]
        sections.append(sections[0])
        object["sections"] = sections
        let duplicate = try JSONDecoder().decode(Course.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(throws: (any Error).self) { try duplicate.validate() }
        object = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        sections = object["sections"] as! [[String: Any]]
        var lessons = sections[0]["lessons"] as! [[String: Any]]
        lessons[0]["prerequisites"] = ["does-not-exist"]
        sections[0]["lessons"] = lessons
        object["sections"] = sections
        let broken = try JSONDecoder().decode(Course.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(throws: (any Error).self) { try broken.validate() }
    }

    @Test func numericAndExactTextPolicies() throws {
        let sample = try #require(Course.bundled().exercises.first)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(sample)) as! [String: Any]
        object["kind"] = "number"
        object["answer"] = "2.5"
        let number = try JSONDecoder().decode(Exercise.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(AnswerChecker.check(" 2,5 ", for: number) == true)
        #expect(AnswerChecker.check("nan", for: number) == false)
        #expect(AnswerChecker.check("inf", for: number) == false)
        #expect(AnswerChecker.check("2.5001", for: number) == false)
        object["kind"] = "text"
        object["answer"] = "Case Sensitive"
        let text = try JSONDecoder().decode(Exercise.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(AnswerChecker.check("Case Sensitive", for: text) == true)
        #expect(AnswerChecker.check("case sensitive", for: text) == false)
    }
}
