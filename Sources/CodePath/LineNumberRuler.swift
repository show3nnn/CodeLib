import AppKit
import LearningCore

@MainActor
final class LineNumberRuler: NSRulerView {
    private weak var editor: NSTextView?
    private(set) var lines = SourceLines("")
    private var source = ""
    private var labelFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    override var isFlipped: Bool { true }

    init(scrollView: NSScrollView, editor: NSTextView) {
        self.editor = editor
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = editor
        ruleThickness = 44
        setAccessibilityElement(false) // The code remains one accessible, editable document.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
                                              name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    required init(coder: NSCoder) { super.init(coder: coder) }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func scrolled(_ notification: Notification) { needsDisplay = true }

    func refresh() {
        guard let editor else { return }
        if source != editor.string {
            source = editor.string
            lines = SourceLines(source)
        }
        labelFont = .monospacedDigitSystemFont(ofSize: max(10, (editor.font?.pointSize ?? 15) - 2), weight: .regular)
        let width = (String(lines.count) as NSString).size(withAttributes: [.font: labelFont]).width
        let thickness = max(44, ceil(width) + 18)
        if ruleThickness != thickness { ruleThickness = thickness }
        needsDisplay = true
    }

    func visibleLineRange() -> ClosedRange<Int>? {
        guard let editor, let layout = editor.layoutManager, let container = editor.textContainer else { return nil }
        layout.ensureLayout(for: container)
        let origin = editor.textContainerOrigin
        // Use this editor's clip view, not ancestor clipping from the lesson's outer ScrollView.
        let visible = (scrollView?.documentVisibleRect ?? editor.bounds).offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        let firstCharacter = glyphs.location < layout.numberOfGlyphs ? layout.characterIndexForGlyph(at: glyphs.location) : lines.utf16Count
        let lastGlyph = min(NSMaxRange(glyphs), layout.numberOfGlyphs)
        let lastCharacter = lastGlyph > 0 ? layout.characterIndexForGlyph(at: lastGlyph - 1) : 0
        let firstLine = lines.lineIndex(atUTF16Offset: firstCharacter)
        // Include the final empty line represented by TextKit's extra line fragment.
        let lastLine = min(lines.count - 1, lines.lineIndex(atUTF16Offset: lastCharacter) + 1)
        guard firstLine <= lastLine else { return nil }
        return firstLine...lastLine
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()
        guard let editor, let layout = editor.layoutManager, let visibleLines = visibleLineRange() else { return }
        let origin = editor.textContainerOrigin
        for index in visibleLines {
            let offset = lines.starts[index]
            let fragment: NSRect
            if offset < lines.utf16Count {
                let glyph = layout.glyphIndexForCharacter(at: offset)
                fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            } else {
                fragment = layout.extraLineFragmentRect
            }
            let point = convert(NSPoint(x: origin.x, y: fragment.minY + origin.y), from: editor)
            let label = String(index + 1) as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: NSColor.secondaryLabelColor]
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 9, y: point.y), withAttributes: attributes)
        }
    }
}
