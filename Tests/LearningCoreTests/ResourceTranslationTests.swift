import Foundation
import Testing
@testable import LearningCore

struct ResourceTranslationTests {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    private let courseIDs: Set<String> = ["cpp-foundations"]
    private func source(_ resource: ResourceTranslation.Resource) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("Sources/LearningCore/Resources/\(resource.rawValue).json"))
    }
    private func draft(_ resource: ResourceTranslation.Resource) throws -> ResourceTranslation {
        try JSONDecoder().decode(ResourceTranslation.self, from: Data(contentsOf: root.appendingPathComponent("localization/drafts/\(resource.rawValue).en.json")))
    }
    private func fixture(_ draft: ResourceTranslation, texts: [String: String]? = nil, digest: String? = nil,
                         status: CourseTranslation.Status = .draft, resource: ResourceTranslation.Resource? = nil,
                         locale: CourseLocale = .english, format: Int = 1) -> ResourceTranslation {
        ResourceTranslation(formatVersion: format, resource: resource ?? draft.resource, locale: locale,
                            sourceSHA256: digest ?? draft.sourceSHA256, status: status, texts: texts ?? draft.texts)
    }

    @Test func completeDraftsCannotBecomeProductionResources() throws {
        for (resource, count) in [(ResourceTranslation.Resource.catalog, 10), (.releases, 141)] {
            let data = try source(resource)
            let translation = try draft(resource)
            let coverage = try translation.coverage(for: data)
            #expect(coverage.isComplete && coverage.translated == count && coverage.total == count)
            #expect(translation.status == .draft)
            if resource == .catalog {
                #expect(throws: ContentError.resourceTranslationUnreviewed) { try translation.applyCatalog(to: data, availableCourseIDs: courseIDs) }
            } else {
                #expect(throws: ContentError.resourceTranslationUnreviewed) { try translation.applyHistory(to: data) }
            }
        }
        #expect(throws: ContentError.resourceTranslationUnavailable(resource: "catalog", locale: "en")) {
            try CourseCatalog.bundled(availableCourseIDs: courseIDs, locale: .english)
        }
        #expect(throws: ContentError.resourceTranslationUnavailable(resource: "releases", locale: "en")) {
            try ReleaseHistory.bundled(locale: .english)
        }
    }

    @Test func projectionsChangeOnlyTextNotIdentityAvailabilityOrHistory() throws {
        let catalogData = try source(.catalog)
        let originalCatalog = try JSONDecoder().decode(CourseCatalog.self, from: catalogData)
        let catalog = try draft(.catalog).developerCatalogPreview(from: catalogData, availableCourseIDs: courseIDs)
        #expect(catalog.version == originalCatalog.version)
        #expect(catalog.entries.map(\.id) == originalCatalog.entries.map(\.id))
        #expect(catalog.entries.map(\.language) == originalCatalog.entries.map(\.language))
        #expect(catalog.entries.map(\.availability) == originalCatalog.entries.map(\.availability))
        #expect(catalog.entries.filter { $0.availability == .available }.map(\.id) == ["cpp-foundations"])
        #expect(catalog.entries.first?.title == "C++ — from zero to a confident first year")
        #expect(throws: ContentError.invalidCatalog) { try draft(.catalog).developerCatalogPreview(from: catalogData, availableCourseIDs: []) }
        let historyData = try source(.releases)
        let originalHistory = try JSONDecoder().decode(ReleaseHistory.self, from: historyData)
        let history = try draft(.releases).developerHistoryPreview(from: historyData)
        #expect(history.formatVersion == originalHistory.formatVersion)
        #expect(history.releases.map(\.version) == originalHistory.releases.map(\.version))
        for (original, translated) in zip(originalHistory.releases, history.releases) {
            #expect(original.stage == translated.stage && original.date == translated.date)
            #expect(original.features.map(\.id) == translated.features.map(\.id))
            #expect(original.features.map(\.symbol) == translated.features.map(\.symbol))
            #expect(original.improvements.count == translated.improvements.count && original.fixes.count == translated.fixes.count)
            #expect(original.title != translated.title)
        }
        #expect(history.releases.last?.stage == nil && history.releases.last?.date == nil)
        #expect(history.releases.last?.title == "The original working CodePath build")
    }

    @Test func keysSurviveFeatureAndListReordering() throws {
        let data = try source(.releases)
        let translation = try draft(.releases)
        let baseline = try translation.developerHistoryPreview(from: data)
        var document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var notes = try #require(document["releases"] as? [[String: Any]])
        for index in notes.indices {
            for field in ["features", "improvements", "fixes"] {
                let values = try #require(notes[index][field] as? [Any])
                notes[index][field] = Array(values.reversed())
            }
        }
        document["releases"] = notes
        let reordered = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
        // Test-only reviewed-source fixture, not a promotion or rewrite of author fingerprints.
        let synthetic = fixture(translation, digest: CourseTranslation.digest(reordered))
        let projected = try synthetic.developerHistoryPreview(from: reordered)
        for (before, after) in zip(baseline.releases, projected.releases) {
            #expect(after.features.map(\.title) == Array(before.features.map(\.title).reversed()))
            #expect(after.features.map(\.detail) == Array(before.features.map(\.detail).reversed()))
            #expect(after.improvements == Array(before.improvements.reversed()))
            #expect(after.fixes == Array(before.fixes.reversed()))
        }
    }

    @Test func staleWrongTypeUnknownEmptyAndIncompleteTranslationsAreRejected() throws {
        let data = try source(.catalog)
        let translation = try draft(.catalog)
        for invalid in [fixture(translation, digest: "stale"), fixture(translation, locale: .russian), fixture(translation, format: 2)] {
            #expect(throws: ContentError.invalidResourceTranslationSource) { try invalid.coverage(for: data) }
        }
        #expect(throws: ContentError.resourceTranslationMismatch) { try translation.developerHistoryPreview(from: data) }
        var unknown = translation.texts
        unknown["catalog.cpp-foundations.availability"] = "comingSoon"
        #expect(throws: ContentError.resourceTranslationNotReady(missing: 0, unknown: 1)) {
            try fixture(translation, texts: unknown).developerCatalogPreview(from: data, availableCourseIDs: courseIDs)
        }
        var empty = translation.texts
        empty["catalog.cpp-foundations.summary"] = " "
        #expect(throws: ContentError.resourceTranslationNotReady(missing: 1, unknown: 0)) {
            try fixture(translation, texts: empty, status: .reviewed).applyCatalog(to: data, availableCourseIDs: courseIDs)
        }
        var missing = translation.texts
        missing.removeValue(forKey: "catalog.rust-future.title")
        #expect(throws: ContentError.resourceTranslationNotReady(missing: 1, unknown: 0)) {
            try fixture(translation, texts: missing, status: .reviewed).applyCatalog(to: data, availableCourseIDs: courseIDs)
        }
        // Synthetic status exercises the production gate; authored files remain draft.
        #expect(try fixture(translation, status: .reviewed).applyCatalog(to: data, availableCourseIDs: courseIDs).entries.count == 5)
    }

    @Test func historyProjectionDoesNotWriteProgressOrChangeUpdateRouting() throws {
        let data = try source(.releases)
        let original = try JSONDecoder().decode(ReleaseHistory.self, from: data)
        let translated = try draft(.releases).developerHistoryPreview(from: data)
        let current = try #require(original.releases.first?.version)
        let old = try #require(original.releases.last?.version)
        let folder = root.appendingPathComponent(".build/test-data/resource-locale-\(UUID().uuidString)")
        let store = try ProgressStore(url: folder.appendingPathComponent("progress.json"))
        try store.update { document in
            document.profile = LocalProfile(nickname: "Учусь 👩🏽‍💻", avatar: .leaf)
            var onboarding = OnboardingState()
            onboarding.completedVersion = 1
            onboarding.draft = document.profile!
            document.onboarding = onboarding
            document.lastViewedRelease = old
            var task = ExerciseProgress()
            task.draft = ""
            document.exercises["future.unknown"] = task
        }
        let bytes = try Data(contentsOf: store.url)
        let reopened = try ProgressStore(url: store.url).document
        for history in [translated, original, translated] {
            #expect(history.updates(after: reopened.lastViewedRelease, through: current).map(\.version) == original.updates(after: old, through: current).map(\.version))
            #expect(StartupRoute.resolve(document: reopened, current: current) == .releaseHistory)
        }
        #expect(reopened.lastViewedRelease == old)
        #expect(reopened.exercises["future.unknown"]?.draft == "")
        #expect(try Data(contentsOf: store.url) == bytes)
    }
}
