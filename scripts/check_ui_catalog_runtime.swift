import Foundation

/// Developer-only integration check: the catalog remains outside the app.
@main
enum CatalogRuntimeCheck {
    static func main() throws {
        guard CommandLine.arguments.count == 2,
              let bundle = Bundle(url: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)) else {
            throw CheckError.invalidBundle
        }
        let en = Locale(identifier: "en")
        var checks = 0
        func check(_ actual: String, _ expected: String) throws {
            guard actual == expected else { throw CheckError.mismatch(actual: actual, expected: expected) }
            checks += 1
        }

        for count in [0, 1, 2, 11, 21, 101] {
            let unit = PluralPresentation.courseUnit(.tasks, count: count, locale: en)
            let progress = PluralPresentation.taskProgress(1, total: count, locale: en)
            let topic = PluralPresentation.topicProgress(.lessons, done: 1, total: count, locale: en)
            let singular = count == 1
            try check(unit.key, singular ? "%lld задание" : "%lld заданий")
            try check(progress.key, singular ? "%lld из %lld задания" : "%lld из %lld заданий")
            try check(topic.key, singular ? "%lld/%lld урок" : "%lld/%lld уроков")
            if singular {
                try check(String(localized: "\(count) задание", bundle: bundle, locale: en), "\(count) task")
                try check(String(localized: "\(1) из \(count) задания", bundle: bundle, locale: en), "1 of \(count) task")
                try check(String(localized: "\(1)/\(count) урок", bundle: bundle, locale: en), "1/\(count) lesson")
            } else {
                try check(String(localized: "\(count) заданий", bundle: bundle, locale: en), "\(count) tasks")
                try check(String(localized: "\(1) из \(count) заданий", bundle: bundle, locale: en), "1 of \(count) tasks")
                try check(String(localized: "\(1)/\(count) уроков", bundle: bundle, locale: en), "1/\(count) lessons")
            }
        }
        try check(String(localized: "Вывод совпал", bundle: bundle, locale: en), "Output matched")
        try check(String(localized: "(пусто)", bundle: bundle, locale: en), "(empty)")
        let name = "👩🏽‍💻 %@"
        try check(String(localized: "С возвращением, \(name).", bundle: bundle, locale: en), "Welcome back, \(name).")
        print("UI catalog runtime: \(checks) checks; developer-only English resources")
    }

    enum CheckError: Error {
        case invalidBundle
        case mismatch(actual: String, expected: String)
    }
}
