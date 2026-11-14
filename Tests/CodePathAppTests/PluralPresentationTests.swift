import Foundation
import Testing
@testable import CodePathApp

struct PluralPresentationTests {
    @Test func russianAndEnglishCardinalFormsDiffer() {
        let ru = Locale(identifier: "ru_RU"), en = Locale(identifier: "en_US")
        for n in [1, 21, 101] { #expect(PluralPresentation.form(n, locale: ru) == .one) }
        for n in [2, 3, 4, 22, 104] { #expect(PluralPresentation.form(n, locale: ru) == .few) }
        for n in [0, 5, 11, 12, 13, 14, 25, 111] { #expect(PluralPresentation.form(n, locale: ru) == .other) }
        #expect(PluralPresentation.form(1, locale: en) == .one)
        for n in [0, 2, 11, 21, 101] { #expect(PluralPresentation.form(n, locale: en) == .other) }
        #expect(PluralPresentation.form(Int.min, locale: ru) == .other)
    }

    @Test func resourceUsesExplicitLocaleAndRussianFallback() {
        let resource = PluralPresentation.lessonTasks(21, minutes: 20)
        #expect(resource.locale == PresentationLocale.locale)
        #expect(String(localized: resource) == "21 задание · ~20 мин")
        #expect(String(localized: PluralPresentation.lessonTasks(2, minutes: 7)) == "2 задания · ~7 мин")
        #expect(String(localized: PluralPresentation.lessonTasks(11, minutes: 5)) == "11 заданий · ~5 мин")
        #expect(PluralPresentation.lessonTasks(21, minutes: 20, locale: Locale(identifier: "en_US")).locale.identifier == "en_US")
        #expect(String(localized: PluralPresentation.taskProgress(1, total: 1)) == "1 из 1 задания")
        #expect(String(localized: PluralPresentation.taskProgress(1, total: 2)) == "1 из 2 заданий")
        #expect(String(localized: PluralPresentation.taskProgress(1, total: 21, completed: true)) == "1 из 21 задания завершено")
        #expect(String(localized: PluralPresentation.taskProgress(1, total: 11, completed: true)) == "1 из 11 заданий завершено")
        #expect(String(localized: PluralPresentation.metricLabel(.tasks, count: 1)) == "задание завершено")
        #expect(String(localized: PluralPresentation.metricLabel(.tasks, count: 2)) == "задания завершено")
        #expect(String(localized: PluralPresentation.metricLabel(.lessons, count: 21)) == "урок завершён")
        #expect(String(localized: PluralPresentation.metricLabel(.achievements, count: 5)) == "достижений")
        #expect(String(localized: PluralPresentation.courseUnit(.sections, count: 1)) == "1 раздел")
        #expect(String(localized: PluralPresentation.courseUnit(.sections, count: 2)) == "2 раздела")
        #expect(String(localized: PluralPresentation.courseUnit(.lessons, count: 11)) == "11 уроков")
        #expect(String(localized: PluralPresentation.courseUnit(.tasks, count: 21)) == "21 задание")
    }
}
