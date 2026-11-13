import Foundation
import LearningCore
import Testing
@testable import CodePathApp

@MainActor struct GreetingStyleTests {
    @Test func stylingNeverRewritesFullOrPartiallyTypedCode() {
        for greeting in ProgrammingGreeting.all {
            for length in 0...greeting.code.count {
                let text = String(greeting.code.prefix(length))
                let styled = GreetingCodeStyle.attributed(text, languageID: greeting.id)
                #expect(String(styled.characters) == text)
            }
        }
    }
}
