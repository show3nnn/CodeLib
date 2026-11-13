import Foundation
import LearningCore
import SwiftUI

/// Retain the reason, not a prematurely formatted String, until presentation.
struct AppFailure {
    enum Operation: CaseIterable, Hashable {
        case export, importProgress, reset, restore
    }
    let cause: any Error
    let operation: Operation?

    init(_ cause: any Error, operation: Operation? = nil) {
        self.cause = cause
        self.operation = operation
    }

    // Russian is intentional until the complete app has a real language preference.
    func resource(locale: Locale = Locale(identifier: "ru")) -> LocalizedStringResource {
        let underlying = ErrorPresentation.resource(for: cause, locale: locale)
        guard let operation else { return underlying }
        // Resolve the nested resource using the same explicit locale, not the system language.
        let detail = String(localized: underlying)
        var result: LocalizedStringResource
        switch operation {
        case .export: result = "Не удалось экспортировать: \(detail)"
        case .importProgress: result = "Импорт отменён, текущие данные сохранены: \(detail)"
        case .reset: result = "Сброс не выполнен: \(detail)"
        case .restore: result = "Восстановление не выполнено: \(detail)"
        }
        result.locale = locale
        return result
    }
}

enum PhotoFailure: Error {
    case invalidSource, cropFailed, encodingFailed
}

enum ErrorPresentation {
    static func resource(for error: any Error, locale: Locale = Locale(identifier: "ru")) -> LocalizedStringResource {
        var result: LocalizedStringResource
        switch error {
        case let reason as ContentError:
            result = content(reason)
        case let reason as StorageError:
            switch reason {
            case .unsupportedVersion(let version): result = "Версия данных \(version) не поддерживается. Файл не изменён."
            case .invalidData: result = "Файл прогресса повреждён или содержит недопустимые значения. Файл не изменён."
            case .conflictingRevision: result = "Данные изменены другим экземпляром приложения. Закройте и откройте codelib снова."
            case .locked: result = "Другой процесс записывает прогресс. Повторите сохранение."
            case .protectedExport: result = "Выберите другой файл экспорта: нельзя заменять рабочий прогресс, резервную копию или служебные файлы."
            }
        case let reason as PhotoFailure:
            switch reason {
            case .invalidSource: result = "Выберите PNG, JPEG или HEIC до 12 МиБ и 40 мегапикселей."
            case .cropFailed: result = "Не удалось подготовить аватар."
            case .encodingFailed: result = "Не удалось сохранить уменьшенную фотографию."
            }
        case is DecodingError:
            result = "Файл данных повреждён или имеет неверную структуру."
        default:
            // System/third-party diagnostics are opaque data, never keys or pattern-matched text.
            result = "\(error.localizedDescription)"
        }
        result.locale = locale
        return result
    }

    private static func content(_ reason: ContentError) -> LocalizedStringResource {
        switch reason {
        case .missingCourse: "Отсутствует ресурс курса"
        case .translationUnavailable(let locale): "Полный перевод курса для \(locale) пока недоступен"
        case .invalidCourse: "Неподдерживаемая версия или пустой курс"
        case .invalidID(let id): "Пустой или повторяющийся ID: \(id)"
        case .emptySection(let id): "Пустой раздел \(id)"
        case .invalidLesson(let id): "Неполный урок или неверные зависимости: \(id)"
        case .invalidExercise(let id): "Неполное задание: \(id)"
        case .missingReference(let id): "Нет эталона/примеров: \(id)"
        case .missingAnswer(let id): "Нет ответа: \(id)"
        case .invalidChoices(let id): "Неверные варианты: \(id)"
        case .invalidChoiceLabels(let id): "Неверные переводы вариантов: \(id)"
        case .invalidNumber(let id): "Некорректное число: \(id)"
        case .invalidProfileName: "Введите имя от 1 до 30 символов без переносов строк и управляющих знаков."
        case .invalidAvatarPhoto: "Выберите фотографию заново: нужен локальный PNG-аватар до 256 КиБ."
        case .avatarMismatch: "Фотография не соответствует выбранному аватару."
        case .missingCatalog: "Отсутствует каталог курсов"
        case .invalidCatalog: "Каталог повреждён или ссылается на отсутствующий курс"
        case .invalidAchievements: "Каталог достижений повреждён"
        case .missingAchievementSection(let id): "Раздел достижения отсутствует: \(id)"
        case .invalidAppVersion: "Не удалось прочитать версию сборки codelib"
        case .missingReleaseHistory: "История обновлений отсутствует"
        case .invalidReleaseHistory: "История обновлений повреждена"
        case .invalidTranslationSource: "Перевод имеет неподдерживаемый формат или устарел относительно исходного курса"
        case .translationCourseMismatch: "Перевод относится к другому курсу или уже локализованному содержимому"
        case .translationNotReady(let missing, let unknown): "Перевод не готов: отсутствует \(missing) полей, неизвестных полей \(unknown)"
        case .invalidTranslationFields: "В черновике перевода есть пустые или неизвестные поля"
        case .resourceTranslationUnavailable(let resource, let locale): "Полный перевод ресурса \(resource) для \(locale) пока недоступен"
        case .invalidResourceTranslationSource: "Перевод ресурса имеет неподдерживаемый формат или устарел"
        case .resourceTranslationMismatch: "Перевод относится к другому типу ресурса"
        case .resourceTranslationNotReady(let missing, let unknown): "Перевод ресурса не готов: отсутствует \(missing) полей, неизвестных полей \(unknown)"
        case .resourceTranslationUnreviewed: "Перевод ресурса ещё не прошёл содержательную рецензию"
        case .invalid(let diagnostic): "\(diagnostic)"
        }
    }
}

struct FailureText: View {
    let failure: AppFailure?
    let fallback: LocalizedStringResource
    var body: some View {
        if let failure { Text(failure.resource()) }
        else { Text(fallback) }
    }
}
