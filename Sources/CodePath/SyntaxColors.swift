import AppKit
import LearningCore

@MainActor
enum SyntaxColors {
    private static let palette = Dictionary(uniqueKeysWithValues: CodeTokenKind.allCases.map { kind in
        (kind, NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let (red, green, blue) = components(for: kind, dark: dark)
            return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        })
    })

    static func color(for kind: CodeTokenKind) -> NSColor {
        palette[kind] ?? .textColor
    }

    // Text colors, not bright control accents: both palettes meet AA contrast on editor backgrounds.
    nonisolated static func components(for kind: CodeTokenKind, dark: Bool) -> (Double, Double, Double) {
        switch (dark, kind) {
        case (false, .keyword): (0.55, 0.12, 0.62)
        case (false, .type): (0.13, 0.34, 0.48)
        case (false, .number): (0.15, 0.25, 0.70)
        case (false, .string): (0.67, 0.14, 0.12)
        case (false, .comment): (0.39, 0.40, 0.42)
        case (false, .directive): (0.46, 0.29, 0.15)
        case (true, .keyword): (0.85, 0.57, 0.95)
        case (true, .type): (0.48, 0.82, 0.88)
        case (true, .number): (0.65, 0.75, 1.00)
        case (true, .string): (0.99, 0.62, 0.55)
        case (true, .comment): (0.62, 0.65, 0.68)
        case (true, .directive): (0.94, 0.74, 0.49)
        }
    }

    static func attributed(_ text: String) -> AttributedString {
        let source = NSMutableAttributedString(string: text)
        for token in CodeSyntax.tokens(in: text) {
            source.addAttribute(.foregroundColor, value: color(for: token.kind), range: token.range)
        }
        return AttributedString(source)
    }
}
