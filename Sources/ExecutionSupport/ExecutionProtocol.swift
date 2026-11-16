import Foundation

public enum ExecutionLimits {
    public static let source = 65_536
    public static let input = 65_536
    public static let stream = 65_536
    public static let request = 800_000
    public static let transport = 1_048_576
    public static let file = 65_536
    public static let fileTotal = 65_536
    public static let fileCount = 8
    public static let fileDetail = 2048
}

public enum ExecutionFiles {
    /// Names the guest program itself or the trusted init owns; a fixture must
    /// never overwrite compiler inputs or the produced binary.
    public static let reserved: Set<String> = ["main.cpp", "stdin", "program"]
    /// Plain single path components only. The guest independently re-checks the
    /// same rule before creating anything.
    public static func isValidName(_ name: String) -> Bool {
        guard (1...64).contains(name.count), !reserved.contains(name),
              name != ".", name != ".." else { return false }
        for scalar in name.unicodeScalars {
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", ".", "_", "-": continue
            default: return false
            }
        }
        return true
    }

    static func validMap(_ files: [String: String]?) throws {
        guard let files else { return }
        guard files.count <= ExecutionLimits.fileCount else { throw ExecutionFailure.invalidRequest }
        var total = 0
        for (name, content) in files {
            guard isValidName(name), content.utf8.count <= ExecutionLimits.file else {
                throw ExecutionFailure.invalidRequest
            }
            total += content.utf8.count
        }
        guard total <= ExecutionLimits.fileTotal else { throw ExecutionFailure.invalidRequest }
    }
}

public struct ExecutionRequest: Codable, Sendable {
    public let version: Int
    public let id: UUID
    public let source: String
    public let stdin: String
    public let standard: String
    /// Input files created by the trusted init before the program runs; expected
    /// files are compared inside the guest after it exits. Both stay optional so
    /// existing encoded requests decode unchanged.
    public let files: [String: String]?
    public let expectedFiles: [String: String]?
    public init(source: String, stdin: String, standard: String = "17", id: UUID = UUID(),
                files: [String: String]? = nil, expectedFiles: [String: String]? = nil) {
        version = 1
        self.id = id
        self.source = source
        self.stdin = stdin
        self.standard = standard
        self.files = files
        self.expectedFiles = expectedFiles
    }
    public func validate() throws {
        guard version == 1, ["17", "20"].contains(standard),
              source.utf8.count <= ExecutionLimits.source, stdin.utf8.count <= ExecutionLimits.input else {
            throw ExecutionFailure.invalidRequest
        }
        try ExecutionFiles.validMap(files)
        try ExecutionFiles.validMap(expectedFiles)
    }
}

public enum ExecutionPhase: String, Codable, Sendable {
    case booting, compiling, running
}

public enum ExecutionStatus: String, Codable, Sendable {
    case success, compileError, runtimeError, cpuLimit, outputLimit, timeout, cancelled, backendError
    /// The program exited normally, but produced file content differs from the
    /// verified fixture. Compared inside the guest; names are returned bounded.
    case fileMismatch
}

public struct ExecutionResult: Codable, Sendable {
    public let status: ExecutionStatus
    public let stdout: String
    public let stderr: String
    public let exitCode: Int?
    public let detail: String
    /// Newline-joined names of files that failed verification; empty otherwise.
    public let fileDetail: String?
    public init(status: ExecutionStatus, stdout: String = "", stderr: String = "", exitCode: Int? = nil,
                detail: String = "", fileDetail: String? = nil) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.detail = detail
        self.fileDetail = fileDetail
    }
    public func validate() throws {
        guard stdout.utf8.count <= ExecutionLimits.stream * 3, stderr.utf8.count <= ExecutionLimits.stream * 3,
              detail.utf8.count <= 8192,
              (fileDetail?.utf8.count ?? 0) <= ExecutionLimits.fileDetail,
              exitCode.map({ (-255...255).contains($0) }) ?? true else { throw ExecutionFailure.invalidResponse }
        if status == .success && exitCode != 0 { throw ExecutionFailure.invalidResponse }
        if [.compileError, .runtimeError, .cpuLimit].contains(status) && (exitCode == nil || exitCode == 0) {
            throw ExecutionFailure.invalidResponse
        }
        if status == .fileMismatch && (exitCode == nil || exitCode != 0 || (fileDetail ?? "").isEmpty) {
            throw ExecutionFailure.invalidResponse
        }
    }
}

public struct ExecutionEvent: Codable, Sendable {
    public let version: Int
    public let id: UUID?
    public let phase: ExecutionPhase?
    public let result: ExecutionResult?
    public init(id: UUID?, phase: ExecutionPhase? = nil, result: ExecutionResult? = nil) {
        version = 1
        self.id = id
        self.phase = phase
        self.result = result
    }
    public func validate(for id: UUID) throws {
        guard version == 1, (self.id == id || (self.id == nil && result?.status == .backendError)),
              (phase == nil) != (result == nil) else { throw ExecutionFailure.invalidResponse }
        try result?.validate()
    }
}

public enum ExecutionFailure: Error, Sendable, Equatable {
    case invalidRequest, invalidResponse, missingAssets, modifiedAssets, invalidHelper
    case unavailable, launchFailed, transportFailed, deadline, busy
}

public struct ExecutionBackendFailure: Error {
    public let reason: ExecutionFailure
    public let cause: any Error
    public init(reason: ExecutionFailure, cause: any Error) { self.reason = reason; self.cause = cause }
}

public struct CompilerDiagnostic: Identifiable, Sendable, Equatable {
    public var id: String { "\(line):\(column):\(message)" }
    public let line: Int
    public let column: Int
    public let message: String
    public static func parse(_ text: String) -> [Self] {
        let pattern = #"/work/main\.cpp:(\d+):(\d+): (?:fatal error|error|warning|note): ([^\n]*)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = text as NSString
        return expression.matches(in: text, range: NSRange(location: 0, length: source.length)).prefix(32).compactMap { match in
            guard let line = Int(source.substring(with: match.range(at: 1))),
                  let column = Int(source.substring(with: match.range(at: 2))), line > 0, column > 0 else { return nil }
            return Self(line: line, column: column, message: source.substring(with: match.range(at: 3)))
        }
    }
}
