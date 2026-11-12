import Foundation
import Darwin

public enum Completion: String, Codable, Sendable {
    case unfinished, automatic, selfReviewed
    public var title: String {
        switch self {
        case .unfinished: "Не завершено"
        case .automatic: "Проверено автоматически"
        case .selfReviewed: "Отмечено вами"
        }
    }
}

public struct ExerciseProgress: Codable, Sendable {
    public var draft: String?
    public var answer = ""
    public var attempts = 0
    public var hintLevel = 0
    public var completion: Completion = .unfinished
    public var lastCorrect: Bool?
    public init() {}
}

public struct Preferences: Codable, Sendable {
    public var theme = "system"
    public var textSize: Double = 17
    public var codeSize: Double = 15
    public var syntaxHighlighting = true
    public var showLineNumbers = true
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case theme, textSize, codeSize, syntaxHighlighting, showLineNumbers
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        theme = try values.decode(String.self, forKey: .theme)
        textSize = try values.decode(Double.self, forKey: .textSize)
        codeSize = try values.decode(Double.self, forKey: .codeSize)
        // Additive preferences: version-1 progress files must retain all existing results.
        syntaxHighlighting = try values.decodeIfPresent(Bool.self, forKey: .syntaxHighlighting) ?? true
        showLineNumbers = try values.decodeIfPresent(Bool.self, forKey: .showLineNumbers) ?? true
    }
}

public struct ProgressDocument: Codable, Sendable {
    public var schemaVersion = 1
    public var exercises: [String: ExerciseProgress] = [:]
    public var lastExerciseID: String?
    public var lastStudyDate: Date?
    public var preferences = Preferences()
    public var lastViewedRelease: NumericVersion?
    public var profile: LocalProfile?
    public var onboarding: OnboardingState?
    public init() {}

    public func validate() throws {
        guard schemaVersion == 1 else { throw StorageError.unsupportedVersion(schemaVersion) }
        try profile?.validate()
        if let onboarding {
            guard (0...1).contains(onboarding.completedVersion), onboarding.draft.nickname.count <= 30,
                  onboarding.draft.nickname.utf8.count <= 512 else { throw StorageError.invalidData }
            var avatarCheck = onboarding.draft
            avatarCheck.nickname = "Аватар"
            try avatarCheck.validate()
            if onboarding.step == .appearance || onboarding.completedVersion == 1 { try onboarding.draft.validate() }
            if onboarding.completedVersion == 1 && profile == nil { throw StorageError.invalidData }
        }
        guard ["system", "light", "dark"].contains(preferences.theme),
              (12...28).contains(preferences.textSize), (11...26).contains(preferences.codeSize),
              exercises.values.allSatisfy({ $0.attempts >= 0 && (0...3).contains($0.hintLevel) }) else {
            throw StorageError.invalidData
        }
    }

    public func completed(_ id: String) -> Bool {
        (exercises[id]?.completion ?? .unfinished) != .unfinished
    }

    public func completedCount(in course: Course) -> Int {
        course.exercises.filter { completed($0.id) }.count
    }

    public func lessonCompleted(_ lesson: Lesson) -> Bool {
        !lesson.exercises.isEmpty && lesson.exercises.allSatisfy { completed($0.id) }
    }
}

public enum StorageError: LocalizedError {
    case unsupportedVersion(Int), invalidData
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "Версия данных \(version) не поддерживается. Файл не изменён."
        case .invalidData: "Файл прогресса повреждён или содержит недопустимые значения. Файл не изменён."
        }
    }
}

/// Synchronous small-file persistence. A failed write never updates the in-memory document.
/// A nonblocking advisory lock and revision check reject conflicting writers without lost updates.
public final class ProgressStore {
    public let url: URL
    public var backupURL: URL { url.appendingPathExtension("backup") }
    public private(set) var document: ProgressDocument
    private var revision: Data?

    public init(url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            document = try Self.decode(data)
            revision = data
        } else {
            document = ProgressDocument()
        }
    }

    public static func decode(_ data: Data) throws -> ProgressDocument {
        // Read the header first: future schemas are never treated as an empty file.
        struct Header: Decodable { let schemaVersion: Int }
        let decoder = JSONDecoder()
        let header = try decoder.decode(Header.self, from: data)
        guard header.schemaVersion == 1 else { throw StorageError.unsupportedVersion(header.schemaVersion) }
        let document = try decoder.decode(ProgressDocument.self, from: data)
        try document.validate()
        return document
    }

    public func update(_ mutate: (inout ProgressDocument) -> Void) throws {
        var next = document
        mutate(&next)
        try next.validate()
        try Self.withFileLock(at: url) {
            let current = try FileManager.default.fileExists(atPath: url.path) ? Data(contentsOf: url) : nil
            guard current == revision else {
                throw ContentError.invalid("Данные изменены другим экземпляром приложения. Закройте и откройте codelib снова.")
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(next)
            if let current { try current.write(to: backupURL, options: .atomic) }
            try data.write(to: url, options: .atomic)
            document = next
            revision = data
        }
    }

    private static func withFileLock<T>(at url: URL, _ operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lockURL = url.appendingPathExtension("lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw ContentError.invalid("Другой процесс записывает прогресс. Повторите сохранение.")
        }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }

    /// Recovery follows the same locking protocol as ordinary writes; the backup stays intact.
    @discardableResult
    public static func restoreBackup(at url: URL) throws -> URL? {
        try withFileLock(at: url) {
            let bytes = try Data(contentsOf: url.appendingPathExtension("backup"))
            _ = try decode(bytes)
            var preserved: URL?
            if FileManager.default.fileExists(atPath: url.path) {
                let original = url.appendingPathExtension("preserved-\(UUID().uuidString)")
                try FileManager.default.copyItem(at: url, to: original)
                preserved = original
            }
            try bytes.write(to: url, options: .atomic)
            return preserved
        }
    }

    public func export(to destination: URL) throws {
        try Self.export(document, to: destination, protecting: url)
    }

    /// Export can save an unsaved in-memory draft, but must never bypass the store's write protocol.
    public static func export(_ document: ProgressDocument, to destination: URL, protecting storageURL: URL) throws {
        try document.validate()
        let canonical = destination.standardizedFileURL.resolvingSymlinksInPath()
        let protected = [storageURL, storageURL.appendingPathExtension("backup"), storageURL.appendingPathExtension("lock")]
        let manager = FileManager.default
        func sameFile(_ lhs: URL, _ rhs: URL) -> Bool {
            if lhs.standardizedFileURL.resolvingSymlinksInPath() == rhs.standardizedFileURL.resolvingSymlinksInPath() { return true }
            guard let a = try? manager.attributesOfItem(atPath: lhs.path),
                  let b = try? manager.attributesOfItem(atPath: rhs.path),
                  let aNode = a[.systemFileNumber] as? NSNumber, let bNode = b[.systemFileNumber] as? NSNumber,
                  let aDevice = a[.systemNumber] as? NSNumber, let bDevice = b[.systemNumber] as? NSNumber else { return false }
            return aNode == bNode && aDevice == bDevice
        }
        let storage = storageURL.standardizedFileURL.resolvingSymlinksInPath()
        let isPreserved = canonical.deletingLastPathComponent() == storage.deletingLastPathComponent()
            && canonical.lastPathComponent.hasPrefix(storage.lastPathComponent + ".preserved-")
        guard !isPreserved, !protected.contains(where: { sameFile(destination, $0) }) else {
            throw ContentError.invalid("Выберите другой файл экспорта: нельзя заменять рабочий прогресс, резервную копию или служебные файлы.")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: destination, options: .atomic)
    }

    public func importDocument(from source: URL) throws {
        let imported = try Self.decode(Data(contentsOf: source))
        try update { $0 = imported }
    }

    public func reset() throws { try update { $0 = ProgressDocument() } }
}
