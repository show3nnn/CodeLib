import AppKit
import LearningCore
import SwiftUI

@MainActor
enum GreetingCodeStyle {
    /// Presentation only; preserve every source character, even during partial typing.
    static func attributed(_ text: String, languageID: String) -> AttributedString {
        let source = text as NSString
        let result = NSMutableAttributedString(string: text, attributes: [.foregroundColor: NSColor.textColor])
        let role: CodeTokenKind
        switch languageID {
        case "python": role = .number
        case "javascript": role = .directive
        case "swift": role = .keyword
        default: role = .type
        }
        let quote = source.range(of: "\"").location
        let prefixEnd = quote == NSNotFound ? source.length : quote
        result.addAttribute(.foregroundColor, value: SyntaxColors.color(for: role), range: NSRange(location: 0, length: prefixEnd))
        if quote != NSNotFound {
            let rest = NSRange(location: quote+1, length: source.length-quote-1)
            let closing = source.range(of: "\"", range: rest).location
            let end = closing == NSNotFound ? source.length : closing+1
            result.addAttribute(.foregroundColor, value: SyntaxColors.color(for: .string), range: NSRange(location: quote, length: end-quote))
        }
        return AttributedString(result)
    }
}

struct WelcomeCodeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        WelcomeCodePanel(reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
    }
}

/// Explicit presentation inputs let previews/smoke exercise accessibility paths without changing macOS settings.
struct WelcomeCodePanel: View {
    let reduceMotion: Bool
    let reduceTransparency: Bool
    @State private var playback = GreetingPlayback()
    var body: some View {
        panel
            .task(id: reduceMotion) {
                if reduceMotion { playback.skip(); return }
                do {
                    while !playback.isFinished {
                        try await Task.sleep(for: .milliseconds(40))
                        try Task.checkCancellation()
                        guard !playback.isFinished else { break }
                        var next = playback
                        next.advance()
                        let fade = next.phase == .fading && playback.phase != .fading
                        withAnimation(fade ? .easeOut(duration: 0.25) : nil) { playback = next }
                    }
                } catch { /* Skip, navigation and accessibility changes end decorative work. */ }
            }
    }

    @ViewBuilder private var panel: some View {
        if reduceTransparency {
            content.background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.secondary.opacity(0.3)) }
        } else {
            content.glassEffect(.regular.tint(.green.opacity(0.04)), in: RoundedRectangle(cornerRadius: 18))
                .shadow(color: .green.opacity(0.09), radius: 10)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(playback.greeting.language).font(.headline)
                Spacer()
                Text("\(playback.index+1) / \(ProgrammingGreeting.all.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text(GreetingCodeStyle.attributed(reduceMotion ? playback.greeting.code : playback.visibleText, languageID: playback.greeting.id))
                .font(.system(.title3, design: .monospaced)).frame(minHeight: 60, alignment: .leading)
                .opacity(!reduceMotion && playback.phase == .fading ? 0 : 1)
                .accessibilityLabel("Пример строки вывода на \(playback.greeting.language)")
                .accessibilityValue(playback.greeting.code)
            Text("Hello, World!").font(.callout.monospaced()).foregroundStyle(.secondary)
            Text("Примеры строк вывода, не запуск программ и не отдельные курсы.")
                .font(.caption).foregroundStyle(.secondary)
            if !playback.isFinished && !reduceMotion {
                Button("Пропустить анимацию") { playback.skip() }
            } else {
                Picker("Строка приветствия", selection: Binding(get: { playback.greeting.id }, set: { playback.selectGreeting($0) })) {
                    ForEach(ProgrammingGreeting.all) { greeting in Text(greeting.language).tag(greeting.id) }
                }.pickerStyle(.menu)
            }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
    }
}
