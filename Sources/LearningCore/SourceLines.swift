import Foundation

/// Logical source lines, including an empty final line, in TextKit's UTF-16 coordinates.
public struct SourceLines: Sendable {
    public let starts: [Int]
    public let utf16Count: Int
    public var count: Int { starts.count }

    public init(_ text: String) {
        let units = Array(text.utf16)
        utf16Count = units.count
        var starts = [0]
        var i = 0
        while i < units.count {
            let c = units[i]
            i += 1
            if c == 13 && i < units.count && units[i] == 10 { i += 1 }
            if c == 10 || c == 13 || c == 0x2028 || c == 0x2029 { starts.append(i) }
        }
        self.starts = starts
    }

    /// Zero-based logical line; offsets outside the source are safely clamped.
    public func lineIndex(atUTF16Offset offset: Int) -> Int {
        let offset = min(max(offset, 0), utf16Count)
        var low = 0
        var high = starts.count
        while low + 1 < high {
            let middle = low + (high - low) / 2
            if starts[middle] <= offset { low = middle }
            else { high = middle }
        }
        return low
    }
}
