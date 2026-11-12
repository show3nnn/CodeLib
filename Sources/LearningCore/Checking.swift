import Foundation

public enum AnswerChecker {
    /// nil means this exercise requires self-review, never source-code matching.
    public static func check(_ answer: String, for exercise: Exercise) -> Bool? {
        guard exercise.kind != .code, let expected = exercise.answer else { return nil }
        switch exercise.kind {
        case .code: return nil
        case .choice, .text: return answer.trimmingCharacters(in: .whitespacesAndNewlines) == expected
        case .number:
            guard let actual = Double(answer.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")), actual.isFinite,
                  let target = Double(expected) else { return false }
            return actual == target
        case .output:
            // Preserve meaningful spaces, ignore only final line endings (not blank lines).
            func normalized(_ value: String) -> String {
                var result = value.replacingOccurrences(of: "\r\n", with: "\n")
                if result.hasSuffix("\n") { result.removeLast() }
                return result
            }
            return normalized(answer) == normalized(expected)
        }
    }
}
