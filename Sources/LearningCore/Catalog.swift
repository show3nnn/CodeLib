import Foundation

public enum CourseAvailability: String, Codable, Sendable {
    case available, comingSoon
}

public struct CourseListing: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let language: String
    public let summary: String
    public let availability: CourseAvailability
}

public struct CourseCatalog: Codable, Sendable {
    public let version: Int
    public let entries: [CourseListing]

    public static func bundled(availableCourseIDs: Set<String>) throws -> CourseCatalog {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json") else {
            throw ContentError.invalid("Отсутствует каталог курсов")
        }
        let catalog = try JSONDecoder().decode(CourseCatalog.self, from: Data(contentsOf: url))
        try catalog.validate(availableCourseIDs: availableCourseIDs)
        return catalog
    }

    public func validate(availableCourseIDs: Set<String>) throws {
        guard version == 1, !entries.isEmpty, Set(entries.map(\.id)).count == entries.count,
              entries.allSatisfy({ !$0.id.isEmpty && !$0.title.isEmpty && !$0.language.isEmpty && !$0.summary.isEmpty }),
              entries.filter({ $0.availability == .available }).allSatisfy({ availableCourseIDs.contains($0.id) }) else {
            throw ContentError.invalid("Каталог повреждён или ссылается на отсутствующий курс")
        }
    }
}
