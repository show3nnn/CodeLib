import Foundation
import LearningCore
import Testing
@testable import CodePathApp

@MainActor struct GreetingStyleTests {
    @Test func navigationTaskStatusAndAvatarLabelsStaySeparateFromStableValues() {
        #expect(AppModel.Page.allCases.map(\.rawValue) == ["home", "catalog", "syllabus", "lesson", "progress", "achievements"])
        #expect(AppModel.Page.allCases.map { String(localized: $0.title) } == ["Мои курсы", "Каталог", "Программа C++", "Обучение", "Мой прогресс", "Достижения"])
        for kind in [ExerciseKind.code, .choice, .output, .number, .text] {
            #expect(String(localized: kind.localizedTitle) == kind.title)
        }
        for status in [Completion.unfinished, .automatic, .selfReviewed] {
            #expect(String(localized: status.localizedTitle) == status.title)
        }
        for avatar in LocalProfile.Avatar.allCases {
            #expect(String(localized: avatar.localizedTitle) == avatar.title)
        }
    }

    @Test func categoryResourcesKeepCanonicalCasesAndRussianFallbacks() {
        let labels = AchievementCategory.allCases.map { String(localized: $0.localizedTitle) }
        #expect(labels == AchievementCategory.allCases.map(\.title))
        #expect(Set(labels).count == AchievementCategory.allCases.count)
    }

    @Test func headersAndMetricsKeepLocalizableResourcesAndLiteralUserData() {
        let nickname = "Пилот %@ 👩🏽‍💻"
        let header = PageHeader(eyebrow: "Ваша лаборатория кода", title: "С возвращением, \(nickname)!",
                                subtitle: "Немного теории. Много собственного кода. Один понятный шаг за другим.")
        #expect(String(localized: header.title) == "С возвращением, \(nickname)!")
        #expect(String(localized: header.eyebrow) == "Ваша лаборатория кода")
        let metric = Metric(value: "42", label: "уроков завершено", icon: "book.closed")
        #expect(metric.value == "42")
        #expect(String(localized: metric.label) == "уроков завершено")
    }

    @Test func stylingNeverRewritesFullOrPartiallyTypedCode() {
        for greeting in ProgrammingGreeting.all {
            for length in 0...greeting.code.count {
                let text = String(greeting.code.prefix(length))
                let styled = GreetingCodeStyle.attributed(text, languageID: greeting.id)
                #expect(String(styled.characters) == text)
            }
        }
    }
}
