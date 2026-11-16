import Foundation

/// Runtime-only grading for code exercises whose fixtures are stdin/stdout based.
/// Nothing here compares source text with a reference solution.
public enum OutputComparison {
    /// Terminal-friendly comparison: normalizes CRLF to LF, ignores trailing spaces
    /// and tabs at line ends and trailing empty lines. Leading spaces, internal blank
    /// lines, order and all other characters remain significant.
    public static func matches(_ actual: String, expected: String) -> Bool {
        normalized(actual) == normalized(expected)
    }

    public static func normalized(_ text: String) -> String {
        let unified = text.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = unified.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
            var value = line
            while value.last == " " || value.last == "\t" { value = value.dropLast() }
            return value
        }
        while let last = lines.last, last.isEmpty { lines.removeLast() }
        return lines.joined(separator: "\n")
    }
}

/// One verified fixture selected for in-app grading. `files` are created by the
/// trusted init before the run; `expectedFiles` are compared inside the guest.
public struct GradingFixture: Sendable, Equatable, Identifiable {
    public let index: Int
    public let input: String
    public let expectedOutput: String
    public let files: [String: String]?
    public let expectedFiles: [String: String]?
    public var id: Int { index }
    public init(index: Int, input: String, expectedOutput: String,
                files: [String: String]? = nil, expectedFiles: [String: String]? = nil) {
        self.index = index
        self.input = input
        self.expectedOutput = expectedOutput
        self.files = files
        self.expectedFiles = expectedFiles
    }
}

public extension Exercise {
    /// Every code exercise with verified test cases is gradable: stdin fixtures,
    /// input files and expected file contents all travel through the same trusted
    /// helper into a fresh disposable VM. Nothing here compares source text with a
    /// reference solution.
    var gradingFixtures: [GradingFixture]? {
        guard kind == .code, !testCases.isEmpty else { return nil }
        return testCases.enumerated().map {
            GradingFixture(index: $0.offset + 1, input: $0.element.input, expectedOutput: $0.element.output,
                           files: $0.element.files, expectedFiles: $0.element.expectedFiles)
        }
    }
}
