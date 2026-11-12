import Foundation

public struct Course: Codable, Sendable, Identifiable {
    public let id: String
    public let version: Int
    public let title: String
    public let language: String
    public let availability: CourseAvailability
    public let summary: String
    public let sections: [CourseSection]
    public var lessons: [Lesson] { sections.flatMap(\.lessons) }
    public var exercises: [Exercise] { lessons.flatMap(\.exercises) }

    public static func bundled() throws -> Course {
        guard let url = Bundle.module.url(forResource: "course", withExtension: "json") else {
            throw ContentError.invalid("Отсутствует ресурс курса")
        }
        let course = try JSONDecoder().decode(Course.self, from: Data(contentsOf: url))
        try course.validate()
        return course
    }

    public func validate() throws {
        guard version == 1, availability == .available, !id.isEmpty, !title.isEmpty, !sections.isEmpty else {
            throw ContentError.invalid("Неподдерживаемая версия или пустой курс")
        }
        var ids: Set<String> = [id]
        var previous: Set<String> = []
        func unique(_ id: String) throws {
            guard !id.isEmpty, ids.insert(id).inserted else {
                throw ContentError.invalid("Пустой или повторяющийся ID: \(id)")
            }
        }
        for section in sections {
            try unique(section.id)
            guard !section.title.isEmpty, !section.lessons.isEmpty else {
                throw ContentError.invalid("Пустой раздел \(section.id)")
            }
            for lesson in section.lessons {
                try unique(lesson.id)
                guard !lesson.title.isEmpty, !lesson.theory.isEmpty, !lesson.example.isEmpty,
                      !lesson.microscope.isEmpty, !lesson.exercises.isEmpty,
                      lesson.prerequisites.allSatisfy({ previous.contains($0) }) else {
                    throw ContentError.invalid("Неполный урок или неверные зависимости: \(lesson.id)")
                }
                for exercise in lesson.exercises {
                    try unique(exercise.id)
                    guard !exercise.title.isEmpty, !exercise.prompt.isEmpty,
                          !exercise.explanation.isEmpty, exercise.hints.count == 2,
                          exercise.hints.allSatisfy({ !$0.isEmpty }), !exercise.skills.isEmpty,
                          (1...3).contains(exercise.difficulty) else {
                        throw ContentError.invalid("Неполное задание: \(exercise.id)")
                    }
                    if exercise.kind == .code {
                        guard !exercise.solution.isEmpty, !exercise.testCases.isEmpty,
                              exercise.answer == nil else {
                            throw ContentError.invalid("Нет эталона/примеров: \(exercise.id)")
                        }
                    } else {
                        guard let answer = exercise.answer, !answer.isEmpty else {
                            throw ContentError.invalid("Нет ответа: \(exercise.id)")
                        }
                        if exercise.kind == .choice {
                            guard exercise.choices.count >= 2, Set(exercise.choices).count == exercise.choices.count,
                                  exercise.choices.contains(answer) else {
                                throw ContentError.invalid("Неверные варианты: \(exercise.id)")
                            }
                        }
                        if exercise.kind == .number, Double(answer)?.isFinite != true {
                            throw ContentError.invalid("Некорректное число: \(exercise.id)")
                        }
                    }
                }
                previous.insert(lesson.id)
            }
        }
    }

    public func lesson(containing exerciseID: String?) -> Lesson? {
        lessons.first { lesson in lesson.exercises.contains { $0.id == exerciseID } }
    }

    public func adjacent(to id: String, offset: Int) -> Exercise? {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return nil }
        let (next, overflow) = index.addingReportingOverflow(offset)
        guard !overflow, exercises.indices.contains(next) else { return nil }
        return exercises[next]
    }
}

public struct CourseSection: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let lessons: [Lesson]
}

public struct Lesson: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let minutes: Int
    public let prerequisites: [String]
    public let theory: String
    public let example: String
    public let microscope: String
    public let recap: String
    public let exercises: [Exercise]
}

public enum ExerciseKind: String, Codable, Sendable {
    case code, choice, output, number, text
    public var title: String {
        switch self {
        case .code: "Написать код"
        case .choice: "Выбрать объяснение"
        case .output: "Предсказать вывод"
        case .number: "Числовой ответ"
        case .text: "Короткий ответ"
        }
    }
}

public struct TestCase: Codable, Sendable {
    public let input: String
    public let output: String
    public let files: [String: String]?
    public let expectedFiles: [String: String]?
}

public struct Exercise: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let kind: ExerciseKind
    public let prompt: String
    public let starter: String
    public let solution: String
    public let answer: String?
    public let choices: [String]
    public let hints: [String]
    public let explanation: String
    public let difficulty: Int
    public let skills: [String]
    public let testCases: [TestCase]
}

public enum ContentError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): message }
    }
}
