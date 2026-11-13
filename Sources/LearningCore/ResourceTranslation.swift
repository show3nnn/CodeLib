import Foundation

/// Text-only localization of catalog/history. Version, IDs, availability, dates and symbols stay canonical.
public struct ResourceTranslation: Codable, Sendable {
    public enum Resource: String, Codable, Sendable { case catalog, releases }
    public let formatVersion: Int
    public let resource: Resource
    public let locale: CourseLocale
    public let sourceSHA256: String
    public let status: CourseTranslation.Status
    public let texts: [String: String]

    public static func sourceTexts(in catalog: CourseCatalog) -> [String: String] {
        var result: [String: String] = [:]
        for entry in catalog.entries {
            result["catalog.\(entry.id).title"] = entry.title
            result["catalog.\(entry.id).summary"] = entry.summary
        }
        return result
    }

    public static func listKey(version: NumericVersion, field: String, value: String) -> String {
        CourseTranslation.valueKey(entityID: "release.\(version.rawValue)", field: field, value: value)
    }

    public static func sourceTexts(in history: ReleaseHistory) -> [String: String] {
        var result: [String: String] = [:]
        for note in history.releases {
            let prefix = "release.\(note.version.rawValue)"
            result["\(prefix).title"] = note.title
            result["\(prefix).summary"] = note.summary
            for feature in note.features {
                result["\(prefix).feature.\(feature.id).title"] = feature.title
                result["\(prefix).feature.\(feature.id).detail"] = feature.detail
            }
            for value in note.improvements { result[listKey(version: note.version, field: "improvement", value: value)] = value }
            for value in note.fixes { result[listKey(version: note.version, field: "fix", value: value)] = value }
        }
        return result
    }

    public func coverage(for data: Data) throws -> CourseTranslation.Coverage {
        try validateSource(data)
        let expected: Set<String>
        switch resource {
        case .catalog:
            let source = try JSONDecoder().decode(CourseCatalog.self, from: data)
            // Cross-resource availability is also checked against actual course IDs when applying.
            try source.validate(availableCourseIDs: Set(source.entries.filter { $0.availability == .available }.map(\.id)))
            expected = Set(Self.sourceTexts(in: source).keys)
        case .releases:
            let source = try JSONDecoder().decode(ReleaseHistory.self, from: data)
            try source.validate()
            expected = Set(Self.sourceTexts(in: source).keys)
        }
        let present = Set(texts.keys)
        let nonempty = Set(texts.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.keys)
        return CourseTranslation.Coverage(translated: expected.intersection(nonempty).count, total: expected.count,
                                          missing: expected.subtracting(nonempty).sorted(), unknown: present.subtracting(expected).sorted())
    }

    private func validateSource(_ data: Data) throws {
        guard formatVersion == 1, locale != .russian, sourceSHA256 == CourseTranslation.digest(data) else {
            throw ContentError.invalidResourceTranslationSource
        }
    }

    private func validate(_ data: Data, for expected: Resource, production: Bool) throws {
        guard resource == expected else { throw ContentError.resourceTranslationMismatch }
        let report = try coverage(for: data)
        guard report.isComplete else {
            throw ContentError.resourceTranslationNotReady(missing: report.missing.count, unknown: report.unknown.count)
        }
        if production && status != .reviewed { throw ContentError.resourceTranslationUnreviewed }
    }

    public func applyCatalog(to data: Data, availableCourseIDs: Set<String>) throws -> CourseCatalog {
        try projectedCatalog(from: data, availableCourseIDs: availableCourseIDs, production: true)
    }

    public func developerCatalogPreview(from data: Data, availableCourseIDs: Set<String>) throws -> CourseCatalog {
        try projectedCatalog(from: data, availableCourseIDs: availableCourseIDs, production: false)
    }

    private func projectedCatalog(from data: Data, availableCourseIDs: Set<String>, production: Bool) throws -> CourseCatalog {
        try validate(data, for: .catalog, production: production)
        let source = try JSONDecoder().decode(CourseCatalog.self, from: data)
        try source.validate(availableCourseIDs: availableCourseIDs)
        let result = CourseCatalog(version: source.version, entries: source.entries.map { entry in
            CourseListing(id: entry.id, title: texts["catalog.\(entry.id).title"]!, language: entry.language,
                          summary: texts["catalog.\(entry.id).summary"]!, availability: entry.availability)
        })
        try result.validate(availableCourseIDs: availableCourseIDs)
        return result
    }

    public func applyHistory(to data: Data) throws -> ReleaseHistory {
        try projectedHistory(from: data, production: true)
    }

    public func developerHistoryPreview(from data: Data) throws -> ReleaseHistory {
        try projectedHistory(from: data, production: false)
    }

    private func projectedHistory(from data: Data, production: Bool) throws -> ReleaseHistory {
        try validate(data, for: .releases, production: production)
        let source = try JSONDecoder().decode(ReleaseHistory.self, from: data)
        let result = ReleaseHistory(formatVersion: source.formatVersion, releases: source.releases.map { note in
            let prefix = "release.\(note.version.rawValue)"
            return ReleaseNote(version: note.version, stage: note.stage, date: note.date,
                               title: texts["\(prefix).title"]!, summary: texts["\(prefix).summary"]!,
                               features: note.features.map { feature in
                                   ReleaseNote.Feature(id: feature.id, symbol: feature.symbol,
                                                       title: texts["\(prefix).feature.\(feature.id).title"]!,
                                                       detail: texts["\(prefix).feature.\(feature.id).detail"]!)
                               },
                               improvements: note.improvements.map { texts[Self.listKey(version: note.version, field: "improvement", value: $0)]! },
                               fixes: note.fixes.map { texts[Self.listKey(version: note.version, field: "fix", value: $0)]! })
        })
        try result.validate()
        return result
    }
}
