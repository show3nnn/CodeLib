import Foundation
import Testing
@testable import LearningCore

struct CodeSyntaxTests {
    func spans(_ text: String) -> [(String, CodeTokenKind)] {
        CodeSyntax.tokens(in: text).map { ((text as NSString).substring(with: $0.range), $0.kind) }
    }

    @Test func keywordsAreWholeIdentifiers() {
        let tokens = spans("int integer; return returning; bool trueValue = true; приветreturn;")
        #expect(tokens.map(\.0) == ["int", "return", "bool", "true"])
        #expect(tokens.map(\.1) == [.type, .keyword, .type, .keyword])
    }

    @Test func commentsAndEscapedLiteralsDoNotExposeKeywords() {
        let text = "// int 7\n/* return */ const char* s = \"if \\\"else\\\"\"; char c = '\\\'';"
        let tokens = spans(text)
        #expect(tokens.map(\.1) == [.comment, .comment, .keyword, .type, .string, .type, .string])
        #expect(tokens[4].0 == "\"if \\\"else\\\"\"")
    }

    @Test func rawStringsRespectTheirDelimiterAndEncodingPrefix() {
        let text = "u8R\"tag(first \" return\n// still text )tag\"; int value;"
        let tokens = spans(text)
        #expect(tokens.count == 2)
        #expect(tokens.first?.1 == .string)
        #expect(tokens.last?.0 == "int")
        #expect(tokens.first?.0 == "u8R\"tag(first \" return\n// still text )tag\"")
    }

    @Test func numbersKeepSeparatorsAndExponentSignsButNotOperators() {
        let tokens = spans("1'000 + 1e-3 + 0x1e+2 + .5f + 0x1.fp+2;")
        #expect(tokens.map(\.0) == ["1'000", "1e-3", "0x1e", "2", ".5f", "0x1.fp+2"])
        #expect(tokens.allSatisfy { $0.1 == .number })
    }

    @Test func directivesAndHeadersUseSeparateTokens() {
        let tokens = spans("  # include <iostream>\nconst int x = 3; // #define\n")
        #expect(tokens.map(\.0) == ["# include", "<iostream>", "const", "int", "3", "// #define"])
        #expect(tokens[0].1 == .directive)
        #expect(tokens[1].1 == .string)
    }

    @Test func unfinishedSourceAndUnicodeHaveSafeUTF16Ranges() {
        for source in ["", "🚀 int x; // привет", "/* unfinished", "\"unfinished", "R\"(unfinished\nreturn",
                       "'", "#", "#include <", "\\", "u8R\"bad delimiter(foo", "\"line\nint n;", "R\"()\""] {
            let tokens = CodeSyntax.tokens(in: source)
            let length = (source as NSString).length
            var end = 0
            for token in tokens {
                #expect(token.range.location >= end)
                #expect(NSMaxRange(token.range) <= length)
                #expect(Range(token.range, in: source) != nil)
                end = NSMaxRange(token.range)
            }
        }
        #expect(spans("🚀 int x;").first?.0 == "int")
    }

    @Test func lineCommentSpliceDoesNotStyleContinuationAsCode() {
        let tokens = spans("// comment \\\nreturn 7;\nint value;")
        #expect(tokens.count == 2)
        #expect(tokens[0].1 == .comment)
        #expect(tokens[0].0.contains("return 7"))
        #expect(tokens[1].0 == "int")
    }

    @Test func lineMapHandlesEmptyFinalLinesUnicodeAndCRLF() {
        #expect(SourceLines("").starts == [0])
        let lines = SourceLines("🚀\r\nкод\n\n")
        #expect(lines.starts == [0, 4, 8, 9])
        #expect(lines.count == 4)
        #expect(lines.lineIndex(atUTF16Offset: 2) == 0)
        #expect(lines.lineIndex(atUTF16Offset: 4) == 1)
        #expect(lines.lineIndex(atUTF16Offset: Int.max) == 3)
        #expect(lines.lineIndex(atUTF16Offset: -1) == 0)
    }
}
