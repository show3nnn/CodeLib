import Foundation
import Testing
@testable import LearningCore

struct AppReleaseTests {
    @Test func versionsCompareNumericallyAndRejectMalformedValues() throws {
        let small = try #require(NumericVersion(rawValue: "0.1.9"))
        let large = try #require(NumericVersion(rawValue: "0.1.10"))
        #expect(small < large)
        for invalid in ["", "0.1", "0.1.1.0", "v0.1.1", "0.01.1", "0.-1.0", "0.1.Alpha", " 0.1.1", "0.1.9999999999999999999999"] {
            #expect(NumericVersion(rawValue: invalid) == nil)
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(NumericVersion.self, from: JSONEncoder().encode(invalid))
            }
        }
        #expect(try JSONDecoder().decode(NumericVersion.self, from: JSONEncoder().encode(large)) == large)
    }

    @Test func packagedMetadataMatchesCurrentHistoryAndRetainsIdentity() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let plist = try Data(contentsOf: root.appendingPathComponent("packaging/Info.plist"))
        let info = try #require(PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any])
        let release = try AppRelease(info: info)
        let history = try ReleaseHistory.bundled()
        #expect(release.version == history.releases.first?.version)
        #expect(release.stage == history.releases.first?.stage)
        #expect(info["CFBundleIdentifier"] as? String == "local.codepath.learning")
        #expect(info["CFBundleName"] as? String == "codelib")
        #expect(release.display.contains(release.version.rawValue))
        #expect(release.display.contains(release.stage.rawValue))
        #expect(throws: (any Error).self) { try AppRelease(info: [:]) }
        for key in ["CFBundleShortVersionString", "CFBundleVersion", "CodelibReleaseStage"] {
            var broken = info
            broken[key] = "invalid"
            #expect(throws: (any Error).self) { try AppRelease(info: broken) }
        }
    }

    @Test func updateSelectionExcludesViewedAndFutureReleases() throws {
        let history = try ReleaseHistory.bundled()
        let current = try #require(history.releases.first?.version)
        let old = try #require(history.releases.last?.version)
        #expect(history.updates(after: nil, through: current).count == history.releases.count)
        #expect(history.updates(after: old, through: current).map(\.version) == history.releases.filter { $0.version > old }.map(\.version))
        #expect(history.updates(after: current, through: current).isEmpty)
        #expect(history.updates(after: nil, through: old).map(\.version) == [old])
    }

    @Test func malformedHistoryIsRejected() throws {
        let history = try ReleaseHistory.bundled()
        let valid = try JSONEncoder().encode(history)
        let base = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        let releases = try #require(base["releases"] as? [[String: Any]])
        for badReleases in [[], Array(releases.reversed()), [releases[0], releases[0]]] {
            var json = base
            json["releases"] = badReleases
            let broken = try JSONDecoder().decode(ReleaseHistory.self, from: JSONSerialization.data(withJSONObject: json))
            #expect(throws: (any Error).self) { try broken.validate() }
        }
    }

    @Test func oldProgressWithoutViewedReleaseRetainsDrafts() throws {
        var document = ProgressDocument()
        var state = ExerciseProgress()
        state.draft = ""
        state.completion = .selfReviewed
        document.exercises["unknown.stable.id"] = state
        let encoded = try JSONEncoder().encode(document)
        let restored = try ProgressStore.decode(encoded)
        #expect(restored.lastViewedRelease == nil)
        #expect(restored.exercises["unknown.stable.id"]?.draft == "")
        #expect(restored.completed("unknown.stable.id"))
    }
}
