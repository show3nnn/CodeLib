import Foundation
import Testing
import LearningCore
@testable import CodePathApp

struct SyntaxColorTests {
    @Test func tokenColorsMeetTextContrastOnLightAndDarkEditorBackgrounds() {
        func luminance(_ rgb: (Double, Double, Double)) -> Double {
            func linear(_ value: Double) -> Double {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(rgb.0) + 0.7152 * linear(rgb.1) + 0.0722 * linear(rgb.2)
        }
        for dark in [false, true] {
            let background = dark ? luminance((0.12, 0.12, 0.12)) : 1.0
            for kind in CodeTokenKind.allCases {
                let foreground = luminance(SyntaxColors.components(for: kind, dark: dark))
                let contrast = (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05)
                #expect(contrast >= 4.5, "\(kind), dark=\(dark), contrast=\(contrast)")
            }
        }
    }
}
