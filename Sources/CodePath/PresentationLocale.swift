import Foundation

/// One presentation policy, not the macOS language and not a persisted language switch.
/// Keep Russian until UI, course and resources can be enabled together.
enum PresentationLocale {
    static let locale = Locale(identifier: "ru")

    static func resource(_ value: LocalizedStringResource) -> LocalizedStringResource {
        var result = value
        result.locale = locale
        return result
    }

    static func date(_ value: Date, includeTime: Bool = false, timeZone: TimeZone = .current) -> String {
        value.formatted(Date.FormatStyle(date: .abbreviated, time: includeTime ? .shortened : .omitted,
                                        locale: locale, calendar: Calendar(identifier: .gregorian), timeZone: timeZone))
    }

    static var percent: FloatingPointFormatStyle<Double>.Percent {
        .percent.precision(.fractionLength(0)).locale(locale)
    }
}
