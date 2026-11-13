import Foundation
import LearningCore
import Testing
@testable import CodePathApp

@MainActor struct PresentationLocaleTests {
    @Test func quitWarningUsesLocalizedNativeResourcesWithoutPresentingADialog() {
        let alert = AppDelegate.unsavedChangesAlert()
        #expect(alert.messageText == "Изменения не сохранены")
        #expect(alert.informativeText.contains("повторить сохранение"))
        #expect(alert.buttons.map(\.title) == ["Остаться", "Выйти без сохранения"])
    }

    @Test func resourcesUseAppLocaleWithoutChangingIdentifiersOrParameters() {
        #expect(PresentationLocale.locale.identifier == "ru")
        let original = LocalizedStringResource("С возвращением, \("A %@ 👩🏽‍💻")!", locale: Locale(identifier: "en"))
        let localized = PresentationLocale.resource(original)
        #expect(original.locale.identifier == "en")
        #expect(localized.locale == PresentationLocale.locale)
        #expect(String(localized: localized) == "С возвращением, A %@ 👩🏽‍💻!")
        for page in AppModel.Page.allCases { #expect(page.title.locale == PresentationLocale.locale) }
        for avatar in LocalProfile.Avatar.allCases { #expect(avatar.localizedTitle.locale == PresentationLocale.locale) }
        for category in AchievementCategory.allCases { #expect(category.localizedTitle.locale == PresentationLocale.locale) }
        for kind in [ExerciseKind.code, .choice, .output, .number, .text] {
            #expect(kind.localizedTitle.locale == PresentationLocale.locale)
        }
        for status in [Completion.unfinished, .automatic, .selfReviewed] {
            #expect(status.localizedTitle.locale == PresentationLocale.locale)
        }
        #expect(AppFailure(NSError(domain: "opaque", code: 1)).resource().locale == PresentationLocale.locale)
    }

    @Test func datesUseRussianGregorianPresentationButRespectLocalTimeZone() throws {
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        let west = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let instant = try #require(ISO8601DateFormatter().date(from: "2024-03-01T00:30:00Z"))
        let utcDate = PresentationLocale.date(instant, timeZone: utc)
        let westDate = PresentationLocale.date(instant, timeZone: west)
        #expect(utcDate.contains("мар") && utcDate.contains("2024"))
        #expect(westDate.contains("29") && westDate.contains("фев"))
        #expect(utcDate != westDate)
        let explicit = instant.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened,
            locale: Locale(identifier: "ru"), calendar: Calendar(identifier: .gregorian), timeZone: west))
        #expect(PresentationLocale.date(instant, includeTime: true, timeZone: west) == explicit)
        // Formatting is read-only; storage and study-day computation still use the original Date.
        #expect(instant == ISO8601DateFormatter().date(from: "2024-03-01T00:30:00Z"))
    }

    @Test func percentageUsesExplicitRussianLocaleAndZeroFractionDigits() {
        #expect(PresentationLocale.percent.locale == PresentationLocale.locale)
        let actual = 0.425.formatted(PresentationLocale.percent)
        let expected = 0.425.formatted(.percent.precision(.fractionLength(0)).locale(Locale(identifier: "ru")))
        #expect(actual == expected)
        #expect(actual.contains("42") || actual.contains("43"))
        #expect(!actual.contains(",") && !actual.contains("."))
        #expect(0.0.formatted(PresentationLocale.percent).contains("0"))
        #expect(1.0.formatted(PresentationLocale.percent).contains("100"))
    }
}
