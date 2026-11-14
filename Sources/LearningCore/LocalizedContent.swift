import Foundation

/// A complete, validated content snapshot. Building one never changes progress.
/// The caller must publish it only after every other presentation resource is ready.
public struct LocalizedContent: Sendable {
    public let locale: CourseLocale
    public let course: Course
    public let catalog: CourseCatalog
    public let history: ReleaseHistory

    /// Persist the choice only after this entire content snapshot has loaded.
    /// This does not validate UI strings or authorize exposing a language:
    /// callers must check every presentation resource and resolve pending
    /// edits before calling it, then publish only after the write succeeds.
    @discardableResult
    public func commitContentSelection(to store: ProgressStore) throws -> Self {
        try store.update { $0.preferences.preferredLanguage = locale.rawValue }
        return self
    }

    public static func load(locale: CourseLocale, courseData: Data, catalogData: Data, historyData: Data,
                            courseTranslation: CourseTranslation? = nil,
                            catalogTranslation: ResourceTranslation? = nil,
                            historyTranslation: ResourceTranslation? = nil) throws -> Self {
        let course: Course
        let catalog: CourseCatalog
        let history: ReleaseHistory
        if locale == .russian {
            course = try JSONDecoder().decode(Course.self, from: courseData)
            try course.validate()
            catalog = try JSONDecoder().decode(CourseCatalog.self, from: catalogData)
            try catalog.validate(availableCourseIDs: [course.id])
            history = try JSONDecoder().decode(ReleaseHistory.self, from: historyData)
            try history.validate()
        } else {
            guard let courseTranslation, courseTranslation.locale == locale else {
                throw ContentError.translationUnavailable(locale.rawValue)
            }
            course = try courseTranslation.apply(to: courseData)
            guard let catalogTranslation, catalogTranslation.locale == locale else {
                throw ContentError.resourceTranslationUnavailable(resource: "catalog", locale: locale.rawValue)
            }
            catalog = try catalogTranslation.applyCatalog(to: catalogData, availableCourseIDs: [course.id])
            guard let historyTranslation, historyTranslation.locale == locale else {
                throw ContentError.resourceTranslationUnavailable(resource: "releases", locale: locale.rawValue)
            }
            history = try historyTranslation.applyHistory(to: historyData)
        }
        try AchievementCatalog.validate(course: course)
        return Self(locale: locale, course: course, catalog: catalog, history: history)
    }
}
