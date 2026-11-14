import Foundation

public enum ExecutionLimits {
    public static let source = 65_536
    public static let input = 65_536
    public static let stream = 65_536
    public static let request = 800_000
    public static let transport = 1_048_576
}

public struct ExecutionRequest: Codable, Sendable {
    public let version: Int
    public let id: UUID
    public let source: String
    public let stdin: String
    public let standard: String
    public init(source: String, stdin: String, standard: String = "17", id: UUID = UUID()) {
        version = 1
        self.id = id
        self.source = source
        self.stdin = stdin
        self.standard = standard
    }
    public func validate() throws {
        guard version == 1, ["17", "20"].contains(standard),
              source.utf8.count <= ExecutionLimits.source, stdin.utf8.count <= ExecutionLimits.input else {
            throw ExecutionFailure.invalidRequest
        }
    }
}

public enum ExecutionPhase: String, Codable, Sendable {
    case booting, compiling, running
}

public enum ExecutionStatus: String, Codable, Sendable {
    case success, compileError, runtimeError, cpuLimit, outputLimit, timeout, cancelled, backendError
}

public struct ExecutionResult: Codable, Sendable {
    public let status: ExecutionStatus
    public let stdout: String
    public let stderr: String
    public let exitCode: Int?
    public let detail: String
    public init(status: ExecutionStatus, stdout: String = "", stderr: String = "", exitCode: Int? = nil, detail: String = "") {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.detail = detail
    }
    public func validate() throws {
        guard stdout.utf8.count <= ExecutionLimits.stream * 3, stderr.utf8.count <= ExecutionLimits.stream * 3,
              detail.utf8.count <= 8192,
              exitCode.map({ (-255...255).contains($0) }) ?? true else { throw ExecutionFailure.invalidResponse }
        if status == .success && exitCode != 0 { throw ExecutionFailure.invalidResponse }
        if [.compileError, .runtimeError, .cpuLimit].contains(status) && (exitCode == nil || exitCode == 0) {
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
