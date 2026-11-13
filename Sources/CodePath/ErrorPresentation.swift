import Foundation
import AppKit
import Darwin
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
    func resource(locale: Locale = PresentationLocale.locale) -> LocalizedStringResource {
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

    /// Opaque diagnostics are available on demand, never used as a localization key.
    var diagnostics: String? {
        guard ErrorPresentation.isSystemError(cause) else { return nil }
        let error = cause as NSError
        return "\(error.domain) (\(error.code))\n\(error.localizedDescription)"
    }

    @MainActor func copyDiagnostics() {
        guard let diagnostics else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
    }
}

enum PhotoFailure: Error {
    case invalidSource, cropFailed, encodingFailed
}

enum ErrorPresentation {
    static func resource(for error: any Error, locale: Locale = PresentationLocale.locale) -> LocalizedStringResource {
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
            result = system(error as NSError)
        }
        result.locale = locale
        return result
    }

    static func isSystemError(_ error: any Error) -> Bool {
        !(error is ContentError || error is StorageError || error is PhotoFailure || error is DecodingError)
    }

    private static func system(_ error: NSError) -> LocalizedStringResource {
        // Match documented domain/code pairs only. A misleading description or underlying
        // error must not change the primary reason; the original Error remains in AppFailure.
        switch (error.domain, error.code) {
        case (NSCocoaErrorDomain, NSFileReadNoPermissionError),
             (NSCocoaErrorDomain, NSFileWriteNoPermissionError),
             (NSPOSIXErrorDomain, Int(EACCES)), (NSPOSIXErrorDomain, Int(EPERM)):
            "Нет доступа к файлу. Проверьте разрешения или выберите другое расположение."
        case (NSCocoaErrorDomain, NSFileNoSuchFileError),
             (NSCocoaErrorDomain, NSFileReadNoSuchFileError),
             (NSPOSIXErrorDomain, Int(ENOENT)):
            "Файл или папка не найдены. Проверьте выбранное расположение."
        case (NSCocoaErrorDomain, NSFileWriteOutOfSpaceError), (NSPOSIXErrorDomain, Int(ENOSPC)):
            "На диске недостаточно места. Освободите место и повторите действие."
        case (NSCocoaErrorDomain, NSFileWriteVolumeReadOnlyError), (NSPOSIXErrorDomain, Int(EROFS)):
            "Расположение доступно только для чтения. Выберите другое место для записи."
        case (NSCocoaErrorDomain, NSFileWriteFileExistsError), (NSPOSIXErrorDomain, Int(EEXIST)):
            "Файл уже существует. Выберите другое имя или расположение."
        case (NSCocoaErrorDomain, NSUserCancelledError):
            "Действие отменено."
        default:
            "Не удалось выполнить действие из-за системной ошибки. Повторите попытку; технические сведения доступны в диагностике."
        }
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
        if let failure {
            VStack(alignment: .leading, spacing: 6) {
                Text(failure.resource()).fixedSize(horizontal: false, vertical: true)
                FailureDiagnostics(failure: failure)
            }
        } else { Text(PresentationLocale.resource(fallback)) }
    }
}

struct FailureDiagnostics: View {
    let failure: AppFailure
    var body: some View {
        if let diagnostics = failure.diagnostics {
            DisclosureGroup("Технические сведения") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Диагностика системы может быть на другом языке. Данные никуда не отправляются.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: diagnostics).font(.caption.monospaced()).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Скопировать диагностику") { failure.copyDiagnostics() }
                }
            }
        }
    }
}
