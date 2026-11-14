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

/// One verified stdin/stdout fixture selected for in-app grading.
public struct GradingFixture: Sendable, Equatable, Identifiable {
    public let index: Int
    public let input: String
    public let expectedOutput: String
    public var id: Int { index }
    public init(index: Int, input: String, expectedOutput: String) {
        self.index = index
        self.input = input
        self.expectedOutput = expectedOutput
    }
}

public extension Exercise {
    /// File fixtures cannot be transferred into the isolated VM yet, so such tasks
    /// stay self-reviewed rather than pretending a partial run is a full check.
    var gradingFixtures: [GradingFixture]? {
        guard kind == .code, !testCases.isEmpty else { return nil }
        guard testCases.allSatisfy({
            ($0.files ?? [:]).isEmpty && ($0.expectedFiles ?? [:]).isEmpty
        }) else { return nil }
        return testCases.enumerated().map {
            GradingFixture(index: $0.offset + 1, input: $0.element.input, expectedOutput: $0.element.output)
        }
    }
}
