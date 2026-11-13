import CryptoKit
import Foundation

public enum CourseLocale: String, Codable, Sendable {
    case russian = "ru", english = "en"
}

/// Text-only overlay. Source code, grading values, fixtures and stable IDs are never translated here.
public struct CourseTranslation: Codable, Sendable {
    public let formatVersion: Int
    public let courseID: String
    public let locale: CourseLocale
    public let sourceSHA256: String
    public let status: Status
    public let texts: [String: String]
    public enum Status: String, Codable, Sendable { case draft, reviewed }

    public struct Coverage: Sendable {
        public let translated: Int
        public let total: Int
        public let missing: [String]
        public let unknown: [String]
        public var isComplete: Bool { missing.isEmpty && unknown.isEmpty }
    }

    public static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// A choice/skill key depends on its canonical value, never its array position.
    public static func valueKey(entityID: String, field: String, value: String) -> String {
        "\(entityID).\(field).\(digest(Data(value.utf8)))"
    }

    public static func sourceTexts(in course: Course) -> [String: String] {
        var result = ["\(course.id).title": course.title, "\(course.id).summary": course.summary]
        for section in course.sections {
            result["\(section.id).title"] = section.title
            result["\(section.id).summary"] = section.summary
            for lesson in section.lessons {
                for (field, value) in [("title", lesson.title), ("summary", lesson.summary), ("theory", lesson.theory),
                                       ("microscope", lesson.microscope), ("recap", lesson.recap)] {
                    result["\(lesson.id).\(field)"] = value
                }
                for exercise in lesson.exercises {
                    for (field, value) in [("title", exercise.title), ("prompt", exercise.prompt), ("explanation", exercise.explanation)] {
                        result["\(exercise.id).\(field)"] = value
                    }
                    for (level, hint) in exercise.hints.enumerated() { result["\(exercise.id).hint.\(level + 1)"] = hint }
                    for (field, values) in [("choice", exercise.choices), ("skill", exercise.skills)] {
                        for value in values { result[valueKey(entityID: exercise.id, field: field, value: value)] = value }
                    }
                }
            }
        }
        return result
    }

    public func coverage(for sourceData: Data) throws -> Coverage {
        let course = try sourceCourse(from: sourceData)
        let expected = Set(Self.sourceTexts(in: course).keys)
        let present = Set(texts.keys)
        let nonempty = Set(texts.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.keys)
        return Coverage(translated: expected.intersection(nonempty).count, total: expected.count,
                        missing: expected.subtracting(nonempty).sorted(), unknown: present.subtracting(expected).sorted())
    }

    private func sourceCourse(from data: Data) throws -> Course {
        guard formatVersion == 1, locale != .russian, sourceSHA256 == Self.digest(data) else {
            throw ContentError.invalidTranslationSource
        }
        let course = try JSONDecoder().decode(Course.self, from: data)
        try course.validate()
        guard courseID == course.id, course.exercises.allSatisfy({ $0.choiceLabels == nil }) else {
            throw ContentError.translationCourseMismatch
        }
        return course
    }

    /// Production loading is all-or-nothing: a draft or incomplete translation cannot become a course.
    public func apply(to sourceData: Data) throws -> Course {
        let report = try coverage(for: sourceData)
        guard status == .reviewed, report.isComplete else {
            throw ContentError.translationNotReady(missing: report.missing.count, unknown: report.unknown.count)
        }
        return try projectedCourse(from: sourceData)
    }

    /// Explicit developer preview only; never called by bundled() or exposed as an app language.
    public func developerPreview(from sourceData: Data) throws -> Course {
        let report = try coverage(for: sourceData)
        guard report.unknown.isEmpty, texts.values.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ContentError.invalidTranslationFields
        }
        return try projectedCourse(from: sourceData)
    }

    private func projectedCourse(from sourceData: Data) throws -> Course {
        let source = try sourceCourse(from: sourceData)
        func text(_ id: String, _ field: String, _ fallback: String) -> String { texts["\(id).\(field)"] ?? fallback }
        func value(_ id: String, _ field: String, _ source: String) -> String {
            texts[Self.valueKey(entityID: id, field: field, value: source)] ?? source
        }
        let sections = source.sections.map { section in
            let lessons = section.lessons.map { lesson in
                let exercises = lesson.exercises.map { exercise in
                    let labels = Dictionary(uniqueKeysWithValues: exercise.choices.map { ($0, value(exercise.id, "choice", $0)) })
                    return Exercise(id: exercise.id, title: text(exercise.id, "title", exercise.title), kind: exercise.kind,
                                    prompt: text(exercise.id, "prompt", exercise.prompt), starter: exercise.starter, solution: exercise.solution,
                                    answer: exercise.answer, choices: exercise.choices, choiceLabels: exercise.kind == .choice ? labels : nil,
                                    hints: exercise.hints.enumerated().map { text(exercise.id, "hint.\($0.offset + 1)", $0.element) },
                                    explanation: text(exercise.id, "explanation", exercise.explanation), difficulty: exercise.difficulty,
                                    skills: exercise.skills.map { value(exercise.id, "skill", $0) }, testCases: exercise.testCases)
                }
                return Lesson(id: lesson.id, title: text(lesson.id, "title", lesson.title), summary: text(lesson.id, "summary", lesson.summary),
                              minutes: lesson.minutes, prerequisites: lesson.prerequisites, theory: text(lesson.id, "theory", lesson.theory),
                              example: lesson.example, microscope: text(lesson.id, "microscope", lesson.microscope),
                              recap: text(lesson.id, "recap", lesson.recap), exercises: exercises)
            }
            return CourseSection(id: section.id, title: text(section.id, "title", section.title),
                                 summary: text(section.id, "summary", section.summary), lessons: lessons)
        }
        let course = Course(id: source.id, version: source.version, title: text(source.id, "title", source.title), language: source.language,
                            availability: source.availability, summary: text(source.id, "summary", source.summary), sections: sections)
        try course.validate()
        return course
    }
}
