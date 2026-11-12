import Foundation

public enum CodeTokenKind: Sendable, Hashable, CaseIterable {
    case keyword, type, number, string, comment, directive
}

public struct CodeToken: Sendable {
    /// UTF-16 offsets for TextKit; styling never rewrites the source text.
    public let range: NSRange
    public let kind: CodeTokenKind
}

/// A conservative lexical C++ colorizer, not a parser, compiler or answer checker.
public enum CodeSyntax {
    private static let types: Set<String> = [
        "bool", "char", "char8_t", "char16_t", "char32_t", "double", "float", "int", "long", "short",
        "signed", "unsigned", "void", "wchar_t"
    ]
    private static let keywords: Set<String> = [
        "alignas", "alignof", "and", "and_eq", "asm", "auto", "bitand", "bitor", "break", "case", "catch",
        "class", "compl", "concept", "const", "consteval", "constexpr", "constinit", "const_cast", "continue",
        "co_await", "co_return", "co_yield", "decltype", "default", "delete", "do", "dynamic_cast", "else",
        "enum", "explicit", "export", "extern", "false", "for", "friend", "goto", "if", "inline", "mutable",
        "namespace", "new", "noexcept", "not", "not_eq", "nullptr", "operator", "or", "or_eq", "private",
        "protected", "public", "register", "reinterpret_cast", "requires", "return", "sizeof", "static",
        "static_assert", "static_cast", "struct", "switch", "template", "this", "thread_local", "throw",
        "true", "try", "typedef", "typeid", "typename", "union", "using", "virtual", "volatile", "while",
        "xor", "xor_eq"
    ]

    public static func tokens(in text: String) -> [CodeToken] {
        let units = Array(text.utf16)
        var result: [CodeToken] = []
        var i = 0
        var lineStart = true
        func matches(_ pattern: [UInt16], at index: Int) -> Bool {
            index + pattern.count <= units.count && units[index..<(index + pattern.count)].elementsEqual(pattern)
        }
        func newline(_ c: UInt16) -> Bool { c == 10 || c == 13 || c == 0x2028 || c == 0x2029 }
        func space(_ c: UInt16) -> Bool { c == 32 || c == 9 || c == 11 || c == 12 }
        func digit(_ c: UInt16) -> Bool { (48...57).contains(c) }
        func letter(_ c: UInt16) -> Bool { (65...90).contains(c) || (97...122).contains(c) || c == 95 || c >= 128 }
        func append(_ kind: CodeTokenKind, _ start: Int, _ end: Int) {
            if end > start { result.append(CodeToken(range: NSRange(location: start, length: end - start), kind: kind)) }
        }
        let rawPrefixes = ["R\"", "u8R\"", "uR\"", "UR\"", "LR\""].map { Array($0.utf16) }
        let quotedPrefixes = ["\"", "'", "u8\"", "u\"", "U\"", "L\"", "u8'", "u'", "U'", "L'"].map { Array($0.utf16) }

        while i < units.count {
            let start = i
            let c = units[i]
            if newline(c) { lineStart = true; i += 1; continue }
            if space(c) { i += 1; continue }
            if c == 47 && i + 1 < units.count && units[i + 1] == 47 {
                i += 2
                while i < units.count {
                    if units[i] == 92 && i + 1 < units.count && (units[i + 1] == 10 || units[i + 1] == 13) {
                        i += 2
                        if units[i - 1] == 13 && i < units.count && units[i] == 10 { i += 1 }
                    } else if newline(units[i]) { break }
                    else { i += 1 }
                }
                append(.comment, start, i)
                continue
            }
            if c == 47 && i + 1 < units.count && units[i + 1] == 42 {
                i += 2
                while i < units.count {
                    if newline(units[i]) { lineStart = true }
                    if units[i] == 42 && i + 1 < units.count && units[i + 1] == 47 { i += 2; break }
                    i += 1
                }
                append(.comment, start, i)
                continue
            }
            if c == 35 && lineStart {
                i += 1
                while i < units.count && space(units[i]) { i += 1 }
                let wordStart = i
                while i < units.count && letter(units[i]) { i += 1 }
                append(.directive, start, i)
                let word = String(decoding: units[wordStart..<i], as: UTF16.self)
                if word == "include" {
                    while i < units.count && space(units[i]) { i += 1 }
                    if i < units.count && units[i] == 60 {
                        let headerStart = i
                        i += 1
                        while i < units.count && !newline(units[i]) && units[i] != 62 { i += 1 }
                        if i < units.count && units[i] == 62 { i += 1 }
                        append(.string, headerStart, i)
                    }
                }
                lineStart = false
                continue
            }
            lineStart = false
            var foundRaw = false
            if c == 82 || c == 117 || c == 85 || c == 76 {
                for prefix in rawPrefixes where matches(prefix, at: i) {
                    let delimiterStart = i + prefix.count
                    var cursor = delimiterStart
                    while cursor < units.count && cursor - delimiterStart <= 16 && units[cursor] != 40
                        && units[cursor] > 32 && units[cursor] <= 126 && units[cursor] != 41 && units[cursor] != 92 {
                        cursor += 1
                    }
                    guard cursor < units.count, units[cursor] == 40, cursor - delimiterStart <= 16 else { continue }
                    let close: [UInt16] = [41] + units[delimiterStart..<cursor] + [34]
                    i = cursor + 1
                    while i < units.count && !matches(close, at: i) { i += 1 }
                    if i < units.count { i += close.count }
                    append(.string, start, i)
                    foundRaw = true
                    break
                }
            }
            if foundRaw { continue }
            if let prefix = quotedPrefixes.first(where: { matches($0, at: i) }) {
                let quote = prefix.last!
                i += prefix.count
                while i < units.count {
                    if units[i] == 92 { i = min(i + 2, units.count) }
                    else if units[i] == quote { i += 1; break }
                    else if newline(units[i]) { break }
                    else { i += 1 }
                }
                append(.string, start, i)
                continue
            }
            if digit(c) || (c == 46 && i + 1 < units.count && digit(units[i + 1])) {
                let isHex = c == 48 && i + 1 < units.count && (units[i + 1] == 120 || units[i + 1] == 88)
                i += 1
                while i < units.count {
                    let next = units[i]
                    if digit(next) || letter(next) || next == 46 || next == 39 { i += 1 }
                    else if (next == 43 || next == 45) && i > start {
                        let previous = units[i - 1]
                        if isHex ? (previous == 112 || previous == 80) : (previous == 101 || previous == 69) { i += 1 }
                        else { break }
                    } else { break }
                }
                append(.number, start, i)
                continue
            }
            if letter(c) {
                i += 1
                while i < units.count && (letter(units[i]) || digit(units[i])) { i += 1 }
                let word = String(decoding: units[start..<i], as: UTF16.self)
                if types.contains(word) { append(.type, start, i) }
                else if keywords.contains(word) { append(.keyword, start, i) }
                continue
            }
            i += 1
        }
        return result
    }
}
