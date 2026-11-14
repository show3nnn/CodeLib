import Foundation

/// Integer cardinal forms for the two languages supported by the localization
/// project. This selects resources, never persisted values or identifiers.
enum PluralPresentation {
    enum Form { case one, few, other }

    static func form(_ count: Int, locale: Locale) -> Form {
        let language = locale.language.languageCode?.identifier
        let n = count.magnitude
        if language == "en" { return n == 1 ? .one : .other }
        // The app currently presents Russian; other languages are not offered.
        let last = n % 10, lastTwo = n % 100
        if last == 1 && lastTwo != 11 { return .one }
        if (2...4).contains(last) && !(12...14).contains(lastTwo) { return .few }
        return .other
    }

    static func lessonTasks(_ count: Int, minutes: Int, locale: Locale = PresentationLocale.locale) -> LocalizedStringResource {
        let text: LocalizedStringResource = switch form(count, locale: locale) {
        case .one: "\(count) задание · ~\(minutes) мин"
        case .few: "\(count) задания · ~\(minutes) мин"
        case .other: "\(count) заданий · ~\(minutes) мин"
        }
        var result = text
        result.locale = locale
        return result
    }

    static func taskProgress(_ done: Int, total: Int, completed: Bool = false,
                             locale: Locale = PresentationLocale.locale) -> LocalizedStringResource {
        // After «из», Russian uses the singular genitive only for numbers ending
        // in 1 outside 11–14. English uses singular only for 1.
        let singular = form(total, locale: locale) == .one
        let text: LocalizedStringResource
        if completed {
            text = singular ? "\(done) из \(total) задания завершено" : "\(done) из \(total) заданий завершено"
        } else {
            text = singular ? "\(done) из \(total) задания" : "\(done) из \(total) заданий"
        }
        var result = text
        result.locale = locale
        return result
    }

    enum MetricKind { case tasks, lessons, achievements }
    enum CourseUnit { case sections, lessons, tasks }

    static func courseUnit(_ kind: CourseUnit, count: Int,
                           locale: Locale = PresentationLocale.locale) -> LocalizedStringResource {
        let text: LocalizedStringResource
        switch (kind, form(count, locale: locale)) {
        case (.sections, .one): text = "\(count) раздел"
        case (.sections, .few): text = "\(count) раздела"
        case (.sections, .other): text = "\(count) разделов"
        case (.lessons, .one): text = "\(count) урок"
        case (.lessons, .few): text = "\(count) урока"
        case (.lessons, .other): text = "\(count) уроков"
        case (.tasks, .one): text = "\(count) задание"
        case (.tasks, .few): text = "\(count) задания"
        case (.tasks, .other): text = "\(count) заданий"
        }
        var result = text
        result.locale = locale
        return result
    }

    static func metricLabel(_ kind: MetricKind, count: Int,
                            locale: Locale = PresentationLocale.locale) -> LocalizedStringResource {
        let text: LocalizedStringResource
        switch (kind, form(count, locale: locale)) {
        case (.tasks, .one): text = "задание завершено"
        case (.tasks, .few): text = "задания завершено"
        case (.tasks, .other): text = "заданий завершено"
        case (.lessons, .one): text = "урок завершён"
        case (.lessons, .few): text = "урока завершено"
        case (.lessons, .other): text = "уроков завершено"
        case (.achievements, .one): text = "достижение"
        case (.achievements, .few): text = "достижения"
        case (.achievements, .other): text = "достижений"
        }
        var result = text
        result.locale = locale
        return result
    }
}
