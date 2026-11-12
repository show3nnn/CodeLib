import Foundation

public struct NumericVersion: RawRepresentable, Codable, Comparable, Hashable, Sendable {
    public let rawValue: String
    private var parts: [Int] { rawValue.split(separator: ".").compactMap { Int($0) } }

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ part in
            !part.isEmpty && part.utf8.allSatisfy { (48...57).contains($0) }
                && (part.count == 1 || part.first != "0") && Int(part) != nil
        }) else { return nil }
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.parts.lexicographicallyPrecedes(rhs.parts)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let version = Self(rawValue: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid numeric app version")
        }
        self = version
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct AppRelease: Sendable {
    public enum Stage: String, Codable, Sendable { case alpha = "Alpha", beta = "Beta", stable = "Release" }
    public let version: NumericVersion
    public let build: String
    public let stage: Stage
    public var display: String { "codelib \(version.rawValue) · \(stage.rawValue)" }

    /// Runtime version always comes from the application Info.plist, never a screen constant.
    public init(info: [String: Any]) throws {
        guard let rawVersion = info["CFBundleShortVersionString"] as? String,
              let version = NumericVersion(rawValue: rawVersion),
              let build = info["CFBundleVersion"] as? String, !build.isEmpty,
              build.utf8.allSatisfy({ (48...57).contains($0) }), let number = Int(build), number > 0,
              let rawStage = info["CodelibReleaseStage"] as? String, let stage = Stage(rawValue: rawStage) else {
            throw ContentError.invalid("Не удалось прочитать версию сборки codelib")
        }
        self.version = version
        self.build = build
        self.stage = stage
    }
}

public struct ReleaseNote: Codable, Sendable, Identifiable {
    public let version: NumericVersion
    public let stage: AppRelease.Stage?
    public let date: String?
    public let title: String
    public let summary: String
    public let features: [Feature]
    public let improvements: [String]
    public let fixes: [String]
    public var id: String { version.rawValue }

    public struct Feature: Codable, Sendable, Identifiable {
        public let id: String
        public let symbol: String
        public let title: String
        public let detail: String
    }
}

public struct ReleaseHistory: Codable, Sendable {
    public let formatVersion: Int
    public let releases: [ReleaseNote]

    public static func bundled() throws -> Self {
        guard let url = Bundle.module.url(forResource: "releases", withExtension: "json") else {
            throw ContentError.invalid("История обновлений отсутствует")
        }
        let history = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try history.validate()
        return history
    }

    public func validate() throws {
        guard formatVersion == 1, !releases.isEmpty, Set(releases.map(\.version)).count == releases.count,
              releases.map(\.version) == releases.map(\.version).sorted(by: >),
              releases.allSatisfy({ note in
                  !note.title.isEmpty && !note.summary.isEmpty && !note.features.isEmpty
                      && Set(note.features.map(\.id)).count == note.features.count
                      && note.features.allSatisfy { !$0.id.isEmpty && !$0.symbol.isEmpty && !$0.title.isEmpty && !$0.detail.isEmpty }
              }) else { throw ContentError.invalid("История обновлений повреждена") }
    }

    public func updates(after seen: NumericVersion?, through current: NumericVersion) -> [ReleaseNote] {
        releases.filter { $0.version <= current && (seen == nil || $0.version > seen!) }
    }
}
