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

    @Test func explicitPresentationLocaleFlowsIntoResourcesDatesAndPercent() throws {
        let english = Locale(identifier: "en_US")
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        let instant = try #require(ISO8601DateFormatter().date(from: "2024-03-01T00:30:00Z"))
        let resource: LocalizedStringResource = "Профиль"
        #expect(PresentationLocale.resource(resource, locale: english).locale == english)
        #expect(PresentationLocale.percent(locale: english).locale == english)
        #expect(PresentationLocale.date(instant, timeZone: utc, locale: english) ==
                instant.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: english,
                                                   calendar: Calendar(identifier: .gregorian), timeZone: utc)))
        #expect(PresentationLocale.date(instant, timeZone: utc, locale: english) !=
                PresentationLocale.date(instant, timeZone: utc))
        #expect(PresentationLocale.locale.identifier == "ru")
    }

    @Test func releaseDatesAreCalendarDaysAndUseTheRequestedLocale() {
        let english = Locale(identifier: "en_US")
        let russian = Locale(identifier: "ru_RU")
        let en = PresentationLocale.releaseDate("2026-11-14", locale: english)
        let ru = PresentationLocale.releaseDate("2026-11-14", locale: russian)
        #expect(en.contains("14") && en.contains("2026"))
        #expect(ru.contains("14") && ru.contains("2026"))
        #expect(en != ru)
        #expect(PresentationLocale.releaseDate("2024-02-29", locale: english) != "2024-02-29")
        for invalid in ["2023-02-29", "2026-13-01", "2026-00-01", "2026-11-31",
                        "2026-1-14", "0000-01-01", "2026-11-14T00:00:00Z", "unknown"] {
            #expect(PresentationLocale.releaseDate(invalid, locale: english) == invalid)
        }
    }
}
