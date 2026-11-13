import Foundation
import LearningCore
import Testing
@testable import CodePathApp

struct ErrorPresentationTests {
    @Test func everyContentReasonPreservesRussianFallbackAndLiteralParameters() {
        let id = "future.%@.урок 👩🏽‍💻"
        let reasons: [ContentError] = [
            .missingCourse, .translationUnavailable("en"), .invalidCourse, .invalidID(id), .emptySection(id),
            .invalidLesson(id), .invalidExercise(id), .missingReference(id), .missingAnswer(id),
            .invalidChoices(id), .invalidChoiceLabels(id), .invalidNumber(id),
            .invalidProfileName, .invalidAvatarPhoto, .avatarMismatch, .missingCatalog, .invalidCatalog,
            .invalidAchievements, .missingAchievementSection(id), .invalidAppVersion, .missingReleaseHistory,
            .invalidReleaseHistory, .invalidTranslationSource, .translationCourseMismatch,
            .translationNotReady(missing: 17, unknown: 2), .invalidTranslationFields,
            .resourceTranslationUnavailable(resource: "catalog", locale: "en"), .invalidResourceTranslationSource,
            .resourceTranslationMismatch, .resourceTranslationNotReady(missing: 2, unknown: 1), .resourceTranslationUnreviewed,
            .invalid("Техническое сообщение %@\nбез преобразования")
        ]
        for reason in reasons {
            let failure = AppFailure(reason)
            #expect(failure.cause as? ContentError == reason)
            #expect(String(localized: failure.resource()) == reason.errorDescription)
        }
    }

    @Test func storageReasonsAndOperationContextsUseOneExplicitLocale() {
        let reasons: [StorageError] = [.unsupportedVersion(99), .invalidData, .conflictingRevision, .locked, .protectedExport]
        for reason in reasons {
            #expect(String(localized: AppFailure(reason).resource()) == reason.errorDescription)
        }
        let prefixes: [AppFailure.Operation: String] = [
            .export: "Не удалось экспортировать: ",
            .importProgress: "Импорт отменён, текущие данные сохранены: ",
            .reset: "Сброс не выполнен: ",
            .restore: "Восстановление не выполнено: "
        ]
        for operation in AppFailure.Operation.allCases {
            let failure = AppFailure(StorageError.unsupportedVersion(99), operation: operation)
            #expect(failure.cause as? StorageError == .unsupportedVersion(99))
            #expect(String(localized: failure.resource()) == prefixes[operation]! + StorageError.unsupportedVersion(99).errorDescription!)
            // EN is not bundled: this checks propagation, not a claimed English UI.
            #expect(failure.resource(locale: Locale(identifier: "en")).locale.identifier == "en")
        }
    }

    @Test func decodingAndPhotoErrorsAreTypedButUnknownDiagnosticsStayOpaque() {
        let error = DecodingError.keyNotFound(Key("schemaVersion"), .init(codingPath: [], debugDescription: "private debug text"))
        #expect(String(localized: AppFailure(error).resource()) == "Файл данных повреждён или имеет неверную структуру.")
        for (reason, expected) in [
            (PhotoFailure.invalidSource, "Выберите PNG, JPEG или HEIC до 12 МиБ и 40 мегапикселей."),
            (.cropFailed, "Не удалось подготовить аватар."),
            (.encodingFailed, "Не удалось сохранить уменьшенную фотографию.")
        ] {
            #expect(String(localized: AppFailure(reason).resource()) == expected)
        }
        let opaque = NSError(domain: "custom.domain", code: 7, userInfo: [NSLocalizedDescriptionKey: "Не удалось экспортировать: %@ 🚀"])
        #expect(String(localized: AppFailure(opaque).resource()) == opaque.localizedDescription)
        #expect((AppFailure(opaque).cause as NSError).domain == "custom.domain")
    }

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}
