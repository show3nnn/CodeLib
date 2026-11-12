import Foundation

public struct IndentationEdit: Sendable {
    public let range: NSRange
    public let replacement: String
    public let selection: NSRange
}

public enum CodeIndentation {
    public static func edit(text: String, selection: NSRange, unindent: Bool) -> IndentationEdit {
        let source = text as NSString
        let safeLocation = min(max(0, selection.location), source.length)
        let safeLength = min(max(0, selection.length), source.length - safeLocation)
        let selected = NSRange(location: safeLocation, length: safeLength)
        if !unindent && !(source.substring(with: selected).contains("\n")) {
            return IndentationEdit(range: selected, replacement: "    ",
                                   selection: NSRange(location: selected.location + 4, length: 0))
        }
        // Do not accidentally include the next line when selection ends exactly at its beginning.
        let last = selected.length > 0 ? selected.location + selected.length - 1 : selected.location
        let firstLine = source.lineRange(for: NSRange(location: selected.location, length: 0))
        let lastLine = source.lineRange(for: NSRange(location: last, length: 0))
        let range = NSRange(location: firstLine.location, length: NSMaxRange(lastLine) - firstLine.location)
        let original = source.substring(with: range)
        var lines = original.components(separatedBy: "\n")
        for index in lines.indices {
            if index == lines.count - 1 && lines[index].isEmpty && original.hasSuffix("\n") { continue }
            if unindent {
                if lines[index].hasPrefix("\t") { lines[index].removeFirst() }
                else {
                    let count = lines[index].prefix(4).prefix { $0 == " " }.count
                    lines[index].removeFirst(count)
                }
            } else { lines[index] = "    " + lines[index] }
        }
        let replacement = lines.joined(separator: "\n")
        let selection: NSRange
        if selected.length == 0 {
            let removed = (original as NSString).length - (replacement as NSString).length
            selection = NSRange(location: max(range.location, selected.location - removed), length: 0)
        } else {
            selection = NSRange(location: range.location, length: (replacement as NSString).length)
        }
        return IndentationEdit(range: range, replacement: replacement, selection: selection)
    }
}
