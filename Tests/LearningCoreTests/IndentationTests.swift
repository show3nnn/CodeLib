import Foundation
import Testing
@testable import LearningCore

struct IndentationTests {
    @Test func tabInsertsFourSpaces() {
        let edit = CodeIndentation.edit(text: "int x;", selection: NSRange(location: 0, length: 0), unindent: false)
        #expect(edit.replacement == "    ")
        #expect(edit.selection.location == 4)
    }
    @Test func multilineIndentAndUnindent() {
        let source = "alpha\n  beta\nlast"
        let selection = NSRange(location: 0, length: 13)
        let indent = CodeIndentation.edit(text: source, selection: selection, unindent: false)
        #expect(indent.replacement == "    alpha\n      beta\n")
        let unindent = CodeIndentation.edit(text: indent.replacement, selection: indent.selection, unindent: true)
        #expect(unindent.replacement == "alpha\n  beta\n")
    }
    @Test func shiftTabRemovesAtMostFourLeadingSpaces() {
        let edit = CodeIndentation.edit(text: "  x", selection: NSRange(location: 3, length: 0), unindent: true)
        #expect(edit.replacement == "x")
        #expect(edit.selection.location == 1)
    }
    @Test func unicodeUsesUTF16Ranges() {
        let edit = CodeIndentation.edit(text: "// 🚀\n  код", selection: NSRange(location: 11, length: 0), unindent: true)
        #expect(edit.replacement == "код")
        #expect(edit.selection.location == 9)
    }
    @Test func emptyEditorAcceptsTabAndBacktab() {
        let edit = CodeIndentation.edit(text: "", selection: NSRange(location: 0, length: 0), unindent: false)
        #expect(edit.replacement == "    ")
        let undo = CodeIndentation.edit(text: "", selection: NSRange(location: 0, length: 0), unindent: true)
        #expect(undo.replacement == "")
    }
}
