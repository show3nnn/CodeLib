import Foundation

public struct LocalProfile: Codable, Sendable, Equatable {
    public enum Avatar: String, Codable, Sendable, CaseIterable {
        case initial, leaf, mountain, star, photo
        public var symbol: String {
            switch self {
            case .initial: "person.crop.circle"
            case .leaf: "leaf.fill"
            case .mountain: "mountain.2.fill"
            case .star: "star.fill"
            case .photo: "photo"
            }
        }
        public var title: String {
            switch self {
            case .initial: "Инициал имени"
            case .leaf: "Лист"
            case .mountain: "Горы"
            case .star: "Звезда"
            case .photo: "Фотография"
            }
        }
    }
    public var nickname: String
    public var id: UUID?
    public var createdAt: Date?
    public var avatar: Avatar
    public var photo: Data?
    public var initial: String { String(nickname.prefix(1)).uppercased() }

    public init(nickname: String = "", avatar: Avatar = .initial, photo: Data? = nil) {
        self.id = UUID()
        self.createdAt = Date()
        self.nickname = nickname
        self.avatar = avatar
        self.photo = photo
    }

    public static func normalizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }

    public func validate() throws {
        if let createdAt, !createdAt.timeIntervalSince1970.isFinite { throw StorageError.invalidData }
        let name = Self.normalizedName(nickname)
        guard name == nickname, (1...30).contains(name.count), name.utf8.count <= 512,
              name.unicodeScalars.contains(where: { !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0) && $0.properties.generalCategory != .format }),
              !name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control || $0.properties.generalCategory == .lineSeparator || $0.properties.generalCategory == .paragraphSeparator || (0x202A...0x202E).contains($0.value) || (0x2066...0x2069).contains($0.value) }) else {
            throw ContentError.invalid("Введите имя от 1 до 30 символов без переносов строк и управляющих знаков.")
        }
        if avatar == .photo {
            guard let photo, photo.count >= 24, photo.count <= 262_144,
                  photo.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
                  Array(photo[12..<24]) == [73, 72, 68, 82, 0, 0, 1, 0, 0, 0, 1, 0] else {
                throw ContentError.invalid("Выберите фотографию заново: нужен локальный PNG-аватар до 256 КиБ.")
            }
        } else if photo != nil {
            throw ContentError.invalid("Фотография не соответствует выбранному аватару.")
        }
    }
}

public struct OnboardingState: Codable, Sendable {
    public enum Step: String, Codable, Sendable { case welcome, profile, appearance }
    public var step: Step = .welcome
    public var draft: LocalProfile = .init()
    public var completedVersion = 0
    public init() {}
}

public enum StartupRoute: Equatable, Sendable {
    case onboarding, releaseHistory, workspace
    public static func resolve(document: ProgressDocument, current: NumericVersion?) -> Self {
        guard document.profile != nil, (document.onboarding?.completedVersion ?? 0) >= 1 else { return .onboarding }
        if let current, document.lastViewedRelease.map({ $0 < current }) ?? true { return .releaseHistory }
        return .workspace
    }
}
