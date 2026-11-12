import AppKit
import LearningCore
import SwiftUI

struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    let fontSize: Double
    var syntaxHighlighting = true
    var showLineNumbers = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        // Explicit TextKit 1 supports temporary syntax attributes and a native NSRulerView.
        let view = EditingTextView(usingTextLayoutManager: false)
        view.isRichText = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = NSSize(width: 16, height: 16)
        view.minSize = NSSize(width: 0, height: 260)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.allowsUndo = true
        view.setAccessibilityLabel("Редактор C++. Код сохраняется автоматически. Tab — отступ, Shift Tab — убрать отступ. Control Tab — выйти из редактора.")
        view.delegate = context.coordinator
        view.string = text
        view.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        view.backgroundColor = .textBackgroundColor
        view.textColor = .textColor
        scroll.documentView = view
        scroll.hasVerticalRuler = true
        scroll.verticalRulerView = LineNumberRuler(scrollView: scroll, editor: view)
        scroll.rulersVisible = showLineNumbers
        view.syntaxHighlighting = syntaxHighlighting
        view.refreshPresentation()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? EditingTextView else { return }
        if view.string != text {
            let selection = view.selectedRange()
            view.string = text
            view.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        }
        if view.font?.pointSize != CGFloat(fontSize) {
            view.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        view.typingAttributes = [.font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular), .foregroundColor: NSColor.textColor]
        view.syntaxHighlighting = syntaxHighlighting
        scroll.rulersVisible = showLineNumbers
        view.refreshPresentation()
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        init(_ parent: CodeEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? EditingTextView else { return }
            parent.text = view.string
            view.refreshPresentation()
        }
    }
}

@MainActor
final class EditingTextView: NSTextView {
    var syntaxHighlighting = true
    private var styledText: String?
    private var styledEnabled: Bool?

    func refreshPresentation() {
        (enclosingScrollView?.verticalRulerView as? LineNumberRuler)?.refresh()
        guard !hasMarkedText(), let layout = layoutManager else { return }
        guard styledText != string || styledEnabled != syntaxHighlighting else { return }
        let range = NSRange(location: 0, length: (string as NSString).length)
        layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
        if syntaxHighlighting {
            for token in CodeSyntax.tokens(in: string) {
                layout.addTemporaryAttribute(.foregroundColor, value: SyntaxColors.color(for: token.kind), forCharacterRange: token.range)
            }
        }
        styledText = string
        styledEnabled = syntaxHighlighting
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 && event.modifierFlags.contains(.control) {
            if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(nil) }
            else { window?.selectNextKeyView(nil) }
            return
        }
        super.keyDown(with: event)
    }
    override func insertTab(_ sender: Any?) { indent(unindent: false) }
    override func insertBacktab(_ sender: Any?) { indent(unindent: true) }

    private func indent(unindent: Bool) {
        let edit = CodeIndentation.edit(text: string, selection: selectedRange(), unindent: unindent)
        breakUndoCoalescing()
        let updated = (string as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        replaceWithUndo(updated, selection: edit.selection)
        undoManager?.setActionName(unindent ? "Убрать отступ" : "Добавить отступ")
        breakUndoCoalescing()
    }

    private func replaceWithUndo(_ value: String, selection: NSRange) {
        let oldText = string
        let oldSelection = selectedRange()
        undoManager?.registerUndo(withTarget: self) { target in
            target.replaceWithUndo(oldText, selection: oldSelection)
        }
        textStorage?.replaceCharacters(in: NSRange(location: 0, length: (string as NSString).length), with: value)
        setSelectedRange(selection)
        didChangeText()
    }

    override func insertNewline(_ sender: Any?) {
        let source = string as NSString
        let line = source.substring(with: source.lineRange(for: NSRange(location: selectedRange().location, length: 0)))
        let prefix = String(line.prefix { $0 == " " || $0 == "\t" })
        super.insertNewline(sender)
        if !prefix.isEmpty { insertText(prefix, replacementRange: selectedRange()) }
    }
}

struct CodeBlock: View {
    let code: String
    let fontSize: Double
    var body: some View {
        ScrollView(.horizontal) {
            Text(SyntaxColors.attributed(code)).font(.system(size: fontSize, design: .monospaced))
                .textSelection(.enabled).padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.08)) }
        .accessibilityLabel("Код C++")
    }
}
