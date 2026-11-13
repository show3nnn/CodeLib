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

    public static func bundled(locale: CourseLocale = .russian) throws -> Course {
        guard let url = Bundle.module.url(forResource: "course", withExtension: "json") else {
            throw ContentError.missingCourse
        }
        let data = try Data(contentsOf: url)
        if locale != .russian {
            guard let translationURL = Bundle.module.url(forResource: "course.\(locale.rawValue)", withExtension: "json") else {
                throw ContentError.translationUnavailable(locale.rawValue)
            }
            let translation = try JSONDecoder().decode(CourseTranslation.self, from: Data(contentsOf: translationURL))
            return try translation.apply(to: data)
        }
        let course = try JSONDecoder().decode(Course.self, from: data)
        try course.validate()
        return course
    }

    public func validate() throws {
        guard version == 1, availability == .available, !id.isEmpty, !title.isEmpty, !sections.isEmpty else {
            throw ContentError.invalidCourse
        }
        var ids: Set<String> = [id]
        var previous: Set<String> = []
        func unique(_ id: String) throws {
            guard !id.isEmpty, ids.insert(id).inserted else {
                throw ContentError.invalidID(id)
            }
        }
        for section in sections {
            try unique(section.id)
            guard !section.title.isEmpty, !section.lessons.isEmpty else {
                throw ContentError.emptySection(section.id)
            }
            for lesson in section.lessons {
                try unique(lesson.id)
                guard !lesson.title.isEmpty, !lesson.theory.isEmpty, !lesson.example.isEmpty,
                      !lesson.microscope.isEmpty, !lesson.exercises.isEmpty,
                      lesson.prerequisites.allSatisfy({ previous.contains($0) }) else {
                    throw ContentError.invalidLesson(lesson.id)
                }
                for exercise in lesson.exercises {
                    try unique(exercise.id)
                    guard !exercise.title.isEmpty, !exercise.prompt.isEmpty,
                          !exercise.explanation.isEmpty, exercise.hints.count == 2,
                          exercise.hints.allSatisfy({ !$0.isEmpty }), !exercise.skills.isEmpty,
                          (1...3).contains(exercise.difficulty) else {
                        throw ContentError.invalidExercise(exercise.id)
                    }
                    if exercise.kind == .code {
                        guard !exercise.solution.isEmpty, !exercise.testCases.isEmpty,
                              exercise.answer == nil else {
                            throw ContentError.missingReference(exercise.id)
                        }
                    } else {
                        guard let answer = exercise.answer, !answer.isEmpty else {
                            throw ContentError.missingAnswer(exercise.id)
                        }
                        if exercise.kind == .choice {
                            guard exercise.choices.count >= 2, Set(exercise.choices).count == exercise.choices.count,
                                  exercise.choices.contains(answer) else {
                                throw ContentError.invalidChoices(exercise.id)
                            }
                            if let labels = exercise.choiceLabels {
                                guard Set(labels.keys) == Set(exercise.choices), Set(labels.values).count == labels.count,
                                      labels.values.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                                    throw ContentError.invalidChoiceLabels(exercise.id)
                                }
                            }
                        }
                        if exercise.kind == .number, Double(answer)?.isFinite != true {
                            throw ContentError.invalidNumber(exercise.id)
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
    /// Canonical choice values remain unchanged for existing progress and checking.
    public let choiceLabels: [String: String]?
    public func choiceLabel(for value: String) -> String { choiceLabels?[value] ?? value }
    public var answerLabel: String? { answer.map { kind == .choice ? choiceLabel(for: $0) : $0 } }
    public let hints: [String]
    public let explanation: String
    public let difficulty: Int
    public let skills: [String]
    public let testCases: [TestCase]
}

/// Stable reasons and parameters, independent of UI localization or persisted course data.
public enum ContentError: LocalizedError, Equatable {
    case missingCourse, translationUnavailable(String), invalidCourse, invalidID(String), emptySection(String)
    case invalidLesson(String), invalidExercise(String), missingReference(String), missingAnswer(String)
    case invalidChoices(String), invalidChoiceLabels(String), invalidNumber(String)
    case invalidProfileName, invalidAvatarPhoto, avatarMismatch, missingCatalog, invalidCatalog
    case invalidAchievements, missingAchievementSection(String), invalidAppVersion, missingReleaseHistory, invalidReleaseHistory
    case invalidTranslationSource, translationCourseMismatch, translationNotReady(missing: Int, unknown: Int), invalidTranslationFields
    case resourceTranslationUnavailable(resource: String, locale: String), invalidResourceTranslationSource
    case resourceTranslationMismatch, resourceTranslationNotReady(missing: Int, unknown: Int), resourceTranslationUnreviewed
    /// Opaque developer/legacy diagnostic; never infer a structured reason from its text.
    case invalid(String)
    public var errorDescription: String? {
        switch self {
        case .missingCourse: "Отсутствует ресурс курса"
        case .translationUnavailable(let locale): "Полный перевод курса для \(locale) пока недоступен"
        case .invalidCourse: "Неподдерживаемая версия или пустой курс"
        case .invalidID(let id): "Пустой или повторяющийся ID: \(id)"
        case .emptySection(let id): "Пустой раздел \(id)"
        case .invalidLesson(let id): "Неполный урок или неверные зависимости: \(id)"
        case .invalidExercise(let id): "Неполное задание: \(id)"
        case .missingReference(let id): "Нет эталона/примеров: \(id)"
        case .missingAnswer(let id): "Нет ответа: \(id)"
        case .invalidChoices(let id): "Неверные варианты: \(id)"
        case .invalidChoiceLabels(let id): "Неверные переводы вариантов: \(id)"
        case .invalidNumber(let id): "Некорректное число: \(id)"
        case .invalidProfileName: "Введите имя от 1 до 30 символов без переносов строк и управляющих знаков."
        case .invalidAvatarPhoto: "Выберите фотографию заново: нужен локальный PNG-аватар до 256 КиБ."
        case .avatarMismatch: "Фотография не соответствует выбранному аватару."
        case .missingCatalog: "Отсутствует каталог курсов"
        case .invalidCatalog: "Каталог повреждён или ссылается на отсутствующий курс"
        case .invalidAchievements: "Каталог достижений повреждён"
        case .missingAchievementSection(let id): "Раздел достижения отсутствует: \(id)"
        case .invalidAppVersion: "Не удалось прочитать версию сборки codelib"
        case .missingReleaseHistory: "История обновлений отсутствует"
        case .invalidReleaseHistory: "История обновлений повреждена"
        case .invalidTranslationSource: "Перевод имеет неподдерживаемый формат или устарел относительно исходного курса"
        case .translationCourseMismatch: "Перевод относится к другому курсу или уже локализованному содержимому"
        case .translationNotReady(let missing, let unknown): "Перевод не готов: отсутствует \(missing) полей, неизвестных полей \(unknown)"
        case .invalidTranslationFields: "В черновике перевода есть пустые или неизвестные поля"
        case .resourceTranslationUnavailable(let resource, let locale): "Полный перевод ресурса \(resource) для \(locale) пока недоступен"
        case .invalidResourceTranslationSource: "Перевод ресурса имеет неподдерживаемый формат или устарел"
        case .resourceTranslationMismatch: "Перевод относится к другому типу ресурса"
        case .resourceTranslationNotReady(let missing, let unknown): "Перевод ресурса не готов: отсутствует \(missing) полей, неизвестных полей \(unknown)"
        case .resourceTranslationUnreviewed: "Перевод ресурса ещё не прошёл содержательную рецензию"
        case .invalid(let message): message
        }
    }
}
