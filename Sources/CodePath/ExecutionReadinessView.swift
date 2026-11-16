import SwiftUI

/// A successful check is evidence of a real isolated compilation and run, not a
/// promise that future executions cannot fail. No readiness state is persisted.
struct ExecutionReadinessView: View {
    @Bindable var execution: CodeExecutionController

    var body: some View {
        ExecutionReadinessPanel(
            readiness: execution.readiness,
            isBusy: execution.isBusy,
            isStopping: execution.isStopping,
            onCheck: { execution.checkReadiness() },
            onStop: { execution.cancel() }
        )
    }
}

/// Explicit values so smoke and previews can render every state without a VM,
/// the same pattern as WelcomeCodePanel.
struct ExecutionReadinessPanel: View {
    let readiness: CodeExecutionController.Readiness
    let isBusy: Bool
    var isStopping = false
    let onCheck: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Среда C++", systemImage: "lock.shield").font(.headline)
            Text("Компилятор уже входит в приложение. Проверка запускает небольшую программу в одноразовой изолированной среде; Xcode и Command Line Tools не нужны.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            switch readiness {
            case .unchecked:
                Text("Среда ещё не проверена. Можно продолжить обучение и проверить её позже в настройках.")
                    .foregroundStyle(.secondary)
            case .checking:
                if isStopping {
                    // Same wording as the editor's stop phase; no new catalog key.
                    Label("Останавливаем среду и все процессы…", systemImage: "stop.circle")
                } else {
                    ProgressView("Проверяем компиляцию и запуск…")
                }
            case .ready:
                Label("Последняя проверка успешна: тестовая программа выполнена.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Label("Не удалось проверить среду. Убедитесь, что используете полное приложение на Mac с Apple silicon и доступной виртуализацией, затем повторите проверку.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            case .cancelled:
                Text("Проверка отменена. Её можно повторить позже.").foregroundStyle(.secondary)
            }
            HStack {
                Button("Проверить среду", systemImage: "play.circle") { onCheck() }
                    .disabled(isBusy)
                    .accessibilityIdentifier("execution.readiness.check")
                if readiness == .checking && !isStopping {
                    Button("Остановить проверку") { onStop() }
                }
            }
            Text("Проверка не изменяет учебный прогресс. Если её пропустить, задания и редактор останутся доступны.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("execution.readiness")
    }
}
