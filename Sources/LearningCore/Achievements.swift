import Foundation

public enum AchievementCategory: String, CaseIterable, Sendable {
    case firstSteps, practice, algorithms, persistence, exploration, mastery
    public var title: String {
        switch self {
        case .firstSteps: "Первые шаги"
        case .practice: "Практика"
        case .algorithms: "Алгоритмы"
        case .persistence: "Настойчивость"
        case .exploration: "Исследование"
        case .mastery: "Мастерство"
        }
    }
}

public struct AchievementDefinition: Identifiable, Sendable {
    public enum Criterion: Sendable {
        case completed, automatic, selfReviewed, lessons, sections, section(String), firstTry, hintFree, days, streak, drafts, wholeCourse
    }
    public let id: String
    public let category: AchievementCategory
    public let symbol: String
    public let target: Int
    public let criterion: Criterion
    public let secret: Bool
    public let titles: [String: String]
    public let descriptions: [String: String]
    public func title(locale: String = "ru") -> String { titles[locale] ?? titles["ru"] ?? id }
    public func detail(locale: String = "ru") -> String { descriptions[locale] ?? descriptions["ru"] ?? "" }
}

public enum AchievementCatalog {
    private static func award(_ id: String, _ category: AchievementCategory, _ symbol: String, _ target: Int,
                              _ criterion: AchievementDefinition.Criterion, _ title: String, _ detail: String,
                              _ englishTitle: String, _ englishDetail: String, secret: Bool = false) -> AchievementDefinition {
        AchievementDefinition(id: "award." + id, category: category, symbol: symbol, target: target, criterion: criterion,
                              secret: secret, titles: ["ru": title, "en": englishTitle], descriptions: ["ru": detail, "en": englishDetail])
    }
    public static let all: [AchievementDefinition] = [
        award("checked", .firstSteps, "checkmark.seal", 1, .automatic, "Есть контакт", "Автоматически проверьте один однозначный ответ. Это не запуск C++.", "Contact made", "Pass an automatic check of one unambiguous answer. This is not C++ execution."),
        award("selfreview", .firstSteps, "person.crop.circle.badge.checkmark", 1, .selfReviewed, "Сам себе рецензент", "Отметьте одну задачу с кодом завершённой после самостоятельной проверки.", "Your own reviewer", "Mark one code-writing task complete after reviewing it yourself."),
        award("lesson", .firstSteps, "book.closed", 1, .lessons, "Первая глава — не предисловие", "Завершите все задания одного урока.", "Past the preface", "Complete every task in one lesson."),
        award("five", .practice, "5.circle", 5, .completed, "Пять причин продолжать", "Завершите 5 заданий любым доступным способом.", "Five reasons to continue", "Complete 5 tasks using the available checking or self-review methods."),
        award("ten", .practice, "10.circle", 10, .completed, "Уже не случайность", "Завершите 10 заданий.", "No longer a coincidence", "Complete 10 tasks."),
        award("twentyfive", .practice, "square.stack", 25, .completed, "Стопка решений", "Завершите 25 заданий.", "A stack of solutions", "Complete 25 tasks."),
        award("fifty", .practice, "50.circle", 50, .completed, "Это уже серьёзно", "Завершите 50 заданий.", "Getting serious", "Complete 50 tasks."),
        award("hundred", .practice, "rosette", 100, .completed, "Сотня без магии", "Завершите 100 заданий.", "A hundred, no magic", "Complete 100 tasks."),
        award("twohundred", .mastery, "square.stack.3d.up", 200, .completed, "Солидный багаж", "Завершите 200 заданий.", "Well equipped", "Complete 200 tasks."),
        award("lessonsfive", .mastery, "books.vertical", 5, .lessons, "Вошли в ритм", "Полностью завершите 5 уроков.", "Finding your rhythm", "Fully complete 5 lessons."),
        award("lessonsten", .mastery, "books.vertical.fill", 10, .lessons, "Полка понимания", "Полностью завершите 10 уроков.", "A shelf of understanding", "Fully complete 10 lessons."),
        award("lessonstwentyfive", .mastery, "graduationcap", 25, .lessons, "Не только прочитано", "Полностью завершите 25 уроков.", "More than just reading", "Fully complete 25 lessons."),
        award("section", .firstSteps, "square.grid.2x2", 1, .sections, "Раздел закрыт — путь открыт", "Завершите один раздел курса.", "Chapter closed, path open", "Complete one course section."),
        award("sectionsthree", .mastery, "square.grid.3x3", 3, .sections, "Система складывается", "Завершите 3 раздела курса.", "The pieces fit", "Complete 3 course sections."),
        award("loops", .algorithms, "repeat", 1, .section("cpp.section.loops"), "Кручу-верчу", "Завершите раздел о циклах.", "Around we go", "Complete the loops section."),
        award("sequences", .algorithms, "list.number", 1, .section("cpp.section.sequences"), "Всё по местам", "Завершите раздел о массивах и последовательностях.", "Everything in its place", "Complete the arrays and sequences section."),
        award("algorithmlab", .algorithms, "function", 1, .section("cpp.section.algorithm-lab"), "Границы под контролем", "Завершите весь алгоритмический практикум.", "Boundaries under control", "Complete the entire algorithm lab."),
        award("firsttry", .exploration, "scope", 1, .firstTry, "Ровно в цель", "Получите верный автоматический ответ за единственную попытку в задаче.", "Right on target", "Pass an automatic answer check with exactly one attempt in that task.", secret: true),
        award("hintfree", .practice, "lightbulb.slash", 10, .hintFree, "Без подсказок. Пока", "Завершите 10 заданий, не раскрывая их подсказки или разбор.", "No hints. So far", "Complete 10 tasks without opening their hints or solutions."),
        award("hintfreetwentyfive", .mastery, "sparkle.magnifyingglass", 25, .hintFree, "Собственная опора", "Завершите 25 заданий без раскрытия подсказок или разбора.", "Standing on your own", "Complete 25 tasks without opening hints or solutions."),
        award("days", .persistence, "calendar", 3, .days, "Возвращение — тоже навык", "Работайте с заданиями в 3 разных местных календарных дня.", "Returning is a skill", "Work on tasks on 3 different local calendar days."),
        award("streak", .persistence, "flame", 5, .streak, "Ни дня без точки с запятой", "Работайте с заданиями 5 календарных дней подряд.", "A semicolon a day", "Work on tasks on 5 consecutive calendar days."),
        award("draft", .exploration, "doc.text", 1, .drafts, "Мысли обрели файл", "Сохраните непустой черновик задачи с кодом. Его правильность не оценивается.", "Thoughts on file", "Save a nonempty code-task draft. Its correctness is not assessed."),
        award("course", .mastery, "laurel.leading", 1, .wholeCourse, "Плюсы к плюсам", "Завершите все задания доступного курса C++.", "Plus after plus", "Complete every task in the available C++ course.")
    ]

    public static func validate(course: Course) throws {
        guard all.count == 24, Set(all.map(\.id)).count == all.count,
              all.allSatisfy({ item in !item.symbol.isEmpty && item.target > 0 && ["ru", "en"].allSatisfy { locale in
                  !(item.titles[locale] ?? "").isEmpty && !(item.descriptions[locale] ?? "").isEmpty
              } }) else { throw ContentError.invalid("Каталог достижений повреждён") }
        for item in all {
            if case .section(let id) = item.criterion, !course.sections.contains(where: { $0.id == id }) {
                throw ContentError.invalid("Раздел достижения отсутствует: \(id)")
            }
        }
    }

    public static var soundURL: URL? { Bundle.module.url(forResource: "achievement", withExtension: "wav") }
}

public struct AchievementAward: Codable, Sendable {
    public let recognizedAt: Date
    public let historical: Bool
    public init(recognizedAt: Date, historical: Bool) { self.recognizedAt = recognizedAt; self.historical = historical }
}

public struct AchievementState: Codable, Sendable {
    public var formatVersion = 1
    public var awards: [String: AchievementAward] = [:]
    public var studyDays: Set<String> = []
    public init() {}
}

public enum AchievementEngine {
    public static func dayKey(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func dayDate(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...9999).contains(parts[0]) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              dayKey(date, timeZone: calendar.timeZone) == key else { return nil }
        return date
    }

    public static func validate(_ state: AchievementState) throws {
        guard state.formatVersion == 1, state.studyDays.allSatisfy({ dayDate($0) != nil }),
              state.awards.values.allSatisfy({ $0.recognizedAt.timeIntervalSince1970.isFinite }) else { throw StorageError.invalidData }
    }

    public static func longestStreak(_ days: Set<String>) -> Int {
        var best = 0, current = 0
        var previous: Date?
        for key in days.sorted() {
            guard let date = dayDate(key) else { continue }
            current = previous.map { date.timeIntervalSince($0) == 86400 ? current + 1 : 1 } ?? 1
            best = max(best, current)
            previous = date
        }
        return best
    }

    public static func value(for item: AchievementDefinition, document: ProgressDocument, course: Course) -> Int {
        let completed = course.exercises.filter { document.completed($0.id) }
        switch item.criterion {
        case .completed: return completed.count
        case .automatic: return completed.filter { $0.kind != .code && document.exercises[$0.id]?.completion == .automatic }.count
        case .selfReviewed: return completed.filter { $0.kind == .code && document.exercises[$0.id]?.completion == .selfReviewed }.count
        case .lessons: return course.lessons.filter { document.lessonCompleted($0) }.count
        case .sections: return course.sections.filter { $0.lessons.allSatisfy { document.lessonCompleted($0) } }.count
        case .section(let id): return course.sections.first(where: { $0.id == id }).map { $0.lessons.allSatisfy { document.lessonCompleted($0) } ? 1 : 0 } ?? 0
        case .firstTry: return completed.filter { let state = document.exercises[$0.id]; return $0.kind != .code && state?.completion == .automatic && state?.attempts == 1 }.count
        case .hintFree: return completed.filter { document.exercises[$0.id]?.hintLevel == 0 }.count
        case .days: return document.achievements?.studyDays.count ?? 0
        case .streak: return longestStreak(document.achievements?.studyDays ?? [])
        case .drafts: return course.exercises.filter { $0.kind == .code && !(document.exercises[$0.id]?.draft?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }.count
        case .wholeCourse: return !course.exercises.isEmpty && completed.count == course.exercises.count ? 1 : 0
        }
    }

    /// Returned IDs are new awards only. Unknown historical IDs are retained, and earned awards never regress.
    public static func reconcile(_ document: inout ProgressDocument, course: Course, now: Date, historical: Bool) -> [String] {
        if document.achievements == nil { document.achievements = AchievementState() }
        var added: [String] = []
        for item in AchievementCatalog.all where document.achievements?.awards[item.id] == nil {
            if value(for: item, document: document, course: course) >= item.target {
                document.achievements?.awards[item.id] = AchievementAward(recognizedAt: now, historical: historical)
                added.append(item.id)
            }
        }
        return added
    }
}
