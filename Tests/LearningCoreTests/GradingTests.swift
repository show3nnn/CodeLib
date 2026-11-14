import Foundation
import Testing
@testable import LearningCore

struct GradingTests {
    @Test func comparisonIgnoresOnlyTerminalFormatting() {
        #expect(OutputComparison.matches("42\n", expected: "42"))
        #expect(OutputComparison.matches("42  \n\t\n", expected: "42"))
        #expect(OutputComparison.matches("42\r\n", expected: "42"))
        #expect(OutputComparison.matches("A\nB\n\n", expected: "A\nB"))
        #expect(OutputComparison.matches("A\nB\n", expected: "A\nB\n"))
        #expect(!OutputComparison.matches(" 42", expected: "42"))
        #expect(OutputComparison.matches("42 ", expected: "42"))
        #expect(!OutputComparison.matches("A\n\nB", expected: "A\nB"))
        #expect(!OutputComparison.matches("a", expected: "A"))
        #expect(!OutputComparison.matches("", expected: "0"))
        #expect(!OutputComparison.matches("42", expected: "42\n43"))
    }

    @Test func comparisonKeepsUnicodeAndInternalSpaces() {
        #expect(OutputComparison.matches("Привет, мир\n", expected: "Привет, мир"))
        #expect(!OutputComparison.matches("Привет,мир", expected: "Привет, мир"))
        #expect(OutputComparison.matches("a\tb\n", expected: "a\tb"))
    }

    @Test func bundledCodeTaskSelectsEveryFixtureInOrder() throws {
        let exercise = try #require(Course.bundled().exercises.first { $0.kind == .code && ($0.gradingFixtures?.count ?? 0) >= 2 })
        let fixtures = try #require(exercise.gradingFixtures)
        #expect(fixtures.map(\.index) == Array(1...exercise.testCases.count))
        #expect(fixtures.map(\.input) == exercise.testCases.map(\.input))
        #expect(fixtures.map(\.expectedOutput) == exercise.testCases.map(\.output))
    }

    @Test func nonCodeAndFileTasksAreNotGradable() throws {
        let course = try Course.bundled()
        for exercise in course.exercises where exercise.kind != .code {
            #expect(exercise.gradingFixtures == nil)
        }
        let fileTask = try #require(course.exercises.first {
            $0.kind == .code && $0.testCases.contains { ($0.files ?? [:]).isEmpty == false }
        })
        #expect(fileTask.gradingFixtures == nil)
    }

    @Test func synthesizedFixtureSelectionRejectsMissingOrUnsupportedCases() throws {
        func decode(_ testCases: String) throws -> Exercise {
            let json = """
            {"id":"synthetic","title":"t","kind":"code","prompt":"p","starter":"","solution":"",
             "answer":null,"choices":[],"hints":[],"explanation":"e","difficulty":1,"skills":[],
             "testCases":\(testCases)}
            """
            return try JSONDecoder().decode(Exercise.self, from: Data(json.utf8))
        }
        let plain = try decode("""
        [{"input":"2 3","output":"5"},{"input":"","output":"ok"}]
        """)
        #expect(plain.gradingFixtures?.map(\.index) == [1, 2])
        #expect(plain.gradingFixtures?.map(\.input) == ["2 3", ""])
        #expect(try decode("[]").gradingFixtures == nil)
        #expect(try decode("""
        [{"input":"","output":"x","files":{"input.txt":"1"}}]
        """).gradingFixtures == nil)
        #expect(try decode("""
        [{"input":"","output":"x","expectedFiles":{"out.txt":"1"}}]
        """).gradingFixtures == nil)
    }
}
