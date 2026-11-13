import Foundation

public struct ProgrammingGreeting: Identifiable, Sendable {
    public let id: String
    public let language: String
    public let code: String
    public static let all: [Self] = [
        Self(id: "cpp", language: "C++", code: "std::cout << \"Hello, World!\";"),
        Self(id: "python", language: "Python", code: "print(\"Hello, World!\")"),
        Self(id: "javascript", language: "JavaScript", code: "console.log(\"Hello, World!\");"),
        Self(id: "swift", language: "Swift", code: "print(\"Hello, World!\")"),
        Self(id: "java", language: "Java", code: "System.out.println(\"Hello, World!\");")
    ]
}

/// Finite decorative playback. This never evaluates code or changes learning progress.
public struct GreetingPlayback: Sendable {
    public enum Phase: Sendable { case typing, holding, fading, finished }
    public private(set) var index = 0
    public private(set) var characterCount = 0
    public private(set) var phase: Phase = .typing
    private var phaseTicks = 0
    public var greeting: ProgrammingGreeting { ProgrammingGreeting.all[index] }
    public var visibleText: String { String(greeting.code.prefix(characterCount)) }
    public var isFinished: Bool { phase == .finished }
    public init() {}

    /// Called at a 40ms presentation cadence. Tests advance deterministically without timers.
    public mutating func advance() {
        switch phase {
        case .typing:
            characterCount += 1
            if characterCount >= greeting.code.count { phase = .holding; phaseTicks = 0 }
        case .holding:
            phaseTicks += 1
            if phaseTicks >= 25 {
                phase = index == ProgrammingGreeting.all.count-1 ? .finished : .fading
                phaseTicks = 0
            }
        case .fading:
            phaseTicks += 1
            if phaseTicks >= 8 { index += 1; characterCount = 0; phaseTicks = 0; phase = .typing }
        case .finished: break
        }
    }

    public mutating func skip() {
        characterCount = greeting.code.count
        phase = .finished
        phaseTicks = 0
    }

    public mutating func selectGreeting(_ id: String) {
        guard let index = ProgrammingGreeting.all.firstIndex(where: { $0.id == id }) else { return }
        self.index = index
        skip()
    }
}
