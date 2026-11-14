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

    /// Release notes contain calendar dates, not instants. Format at UTC in both
    /// directions so the displayed day cannot change with the Mac's time zone.
    /// Preserve an unrecognised legacy value rather than inventing a date.
    static func releaseDate(_ value: String, locale: Locale = PresentationLocale.locale) -> String {
        let bytes = Array(value.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ index, byte in
                  index == 4 || index == 7 || (48...57).contains(byte)
              }),
              let year = Int(value.prefix(4)), let month = Int(value.dropFirst(5).prefix(2)),
              let day = Int(value.suffix(2)), year > 0 else { return value }
        let zone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let components = DateComponents(calendar: calendar, timeZone: zone, year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else { return value }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        guard actual.year == year, actual.month == month, actual.day == day else { return value }
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted,
                                               locale: locale, calendar: calendar, timeZone: zone))
    }

    static var percent: FloatingPointFormatStyle<Double>.Percent {
        .percent.precision(.fractionLength(0)).locale(locale)
    }
}
