import ExecutionSupport
import SwiftUI

/// Input and execution results embedded in the main.cpp editor, without
/// a second card or a duplicate set of Run/Stop controls.
struct ExecutionOutputView: View {
    @Bindable var model: AppModel
    let exerciseID: String
    let source: String
    let initialInput: String
    let navigate: (CompilerDiagnostic) -> Void
    @State private var showInput = false
    private var input: Binding<String> {
        Binding(get: { model.execution.inputs[exerciseID] ?? initialInput },
                set: { model.execution.inputs[exerciseID] = $0 })
    }
    private var execution: CodeExecutionController { model.execution }
    private var isCurrent: Bool { execution.exerciseID == exerciseID }
    private var result: ExecutionResult? { isCurrent ? execution.result : nil }
    private var stale: Bool {
        guard isCurrent else { return false }
        guard source == execution.sourceSnapshot else { return true }
        return !execution.isGrading && input.wrappedValue != execution.inputSnapshot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DisclosureGroup(isExpanded: $showInput) {
                TextEditor(text: input).font(.system(size: model.document.preferences.codeSize, design: .monospaced))
                    .frame(height: 80).padding(6)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.1)) }
                    .accessibilityLabel("Входные данные программы").accessibilityIdentifier("execution.stdin")
                    .padding(.top, 8)
                    // Never truncate user input. Oversized requests fail before VM launch.
            } label: {
                Text("Ввод stdin · передаётся целиком перед запуском")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if isCurrent {
                status
                if stale && (result != nil || execution.isBusy) {
                    Label("Показан результат прежнего кода или ввода. Запустите изменённую программу заново.", systemImage: "clock.arrow.circlepath")
                        .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                if let failure = execution.failure {
                    failureView(failure)
                    if let underlying = execution.backendFailure {
                        DisclosureGroup("Технические сведения") {
                            Text(verbatim: String(describing: underlying.cause)).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                }
                if let result {
                    if result.status == .compileError {
                        diagnostics(result.stderr)
                    }
                    output("stdout", text: result.stdout)
                    if !result.stderr.isEmpty { output("stderr · диагностика", text: result.stderr) }
                    if result.status == .backendError && !result.detail.isEmpty {
                        DisclosureGroup("Технические сведения") {
                            Text(verbatim: result.detail).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                }
                if execution.isGrading {
                    ForEach(execution.gradingResults) { item in
                        gradingCase(item)
                    }
                }
            }
            if model.course?.exercises.first(where: { $0.id == exerciseID })?.gradingFixtures != nil {
                Text("«Проверить решение» запускает примеры из условия в изолированной среде и сравнивает вывод. Успешный запуск сам по себе задание не засчитывает.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Для этого задания автоматическая проверка недоступна: запуск не засчитывает решение. Отметьте выполнение вручную.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if model.course?.exercises.first(where: { $0.id == exerciseID })?.testCases.contains(where: { $0.files?.isEmpty == false }) == true {
                Text("Сейчас передаётся только stdin. Файловые примеры не загружаются; файлы Mac недоступны.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(16)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("editor.execution")
            .onAppear { showInput = !input.wrappedValue.isEmpty }
    }

    @ViewBuilder private var status: some View {
        HStack(spacing: 8) {
            if execution.isBusy { ProgressView().controlSize(.small) }
            Group {
                switch execution.state {
                case .idle: Text("Готово к запуску")
                case .verifying: Text("Проверяем подпись и образы среды…")
                case .phase(.booting): Text("Запускаем изолированную среду…")
                case .phase(.compiling): Text("Компилируем C++…")
                case .phase(.running): Text("Программа выполняется…")
                case .stopping: Text("Останавливаем среду и все процессы…")
                case .finished:
                    if execution.isGrading {
                        gradingSummary
                    } else if let result {
                        switch result.status {
                        case .success: Text("Программа завершилась · код 0")
                        case .compileError: Text("Ошибка компиляции")
                        case .runtimeError: Text("Ошибка выполнения · код \(result.exitCode ?? -1)")
                        case .cpuLimit: Text("Превышен лимит процессорного времени")
                        case .outputLimit: Text("Превышен лимит вывода")
                        case .timeout: Text("Превышено время ожидания")
                        case .cancelled: Text("Запуск остановлен")
                        case .backendError: Text("Среда выполнения недоступна")
                        }
                    } else { Text("Запуск не выполнен") }
                }
            }.font(.callout.weight(.medium))
            if execution.isGrading, execution.isBusy, execution.gradingCaseTotal > 0 {
                Text("· пример \(min(execution.gradingCaseIndex + 1, execution.gradingCaseTotal)) из \(execution.gradingCaseTotal)")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine).accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder private var gradingSummary: some View {
        let passed = execution.gradingResults.filter(\.matches).count
        let total = execution.gradingCaseTotal
        if execution.gradingResults.isEmpty {
            Text("Проверка не выполнена")
        } else if passed == total, total > 0 {
            Text("Все примеры пройдены · \(passed) из \(total)")
        } else if execution.gradingResults.count < total {
            Text("Проверка остановлена · пройдено \(passed) из \(total)")
        } else {
            Text("Пройдено \(passed) из \(total)")
        }
    }

    @ViewBuilder private func gradingCase(_ item: GradingCaseResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: item.matches ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(item.matches ? Color.green : Color.orange)
                Text("Пример \(item.index)").font(.callout.weight(.medium))
                Spacer(minLength: 0)
                Text(gradingLabel(item)).font(.caption).foregroundStyle(.secondary)
            }
            if !item.matches {
                if item.status == .compileError { diagnostics(item.stderr) }
                if item.status == .success {
                    if !item.input.isEmpty { output("ввод", text: item.input) }
                    output("ожидалось", text: item.expectedOutput)
                    output("получено", text: item.actualOutput)
                } else if item.status != .compileError, !item.stderr.isEmpty {
                    output("stderr · диагностика", text: item.stderr)
                }
            }
        }
    }

    private func gradingLabel(_ item: GradingCaseResult) -> String {
        switch item.status {
        case .success: item.matches ? "Вывод совпал" : "Другой вывод"
        case .compileError: "Ошибка компиляции"
        case .runtimeError: "Ошибка выполнения · код \(item.exitCode ?? -1)"
        case .cpuLimit: "Лимит процессорного времени"
        case .outputLimit: "Превышен лимит вывода"
        case .timeout: "Превышено время ожидания"
        case .cancelled: "Запуск остановлен"
        case .backendError: "Среда недоступна"
        }
    }

    @ViewBuilder private func diagnostics(_ text: String) -> some View {
        ForEach(Array(CompilerDiagnostic.parse(text).enumerated()), id: \.offset) { _, item in
            Button { navigate(item) } label: {
                HStack(alignment: .top, spacing: 8) {
                    Text("\(item.line):\(item.column)").monospaced()
                    Text(verbatim: item.message).lineLimit(2)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.left")
                }.font(.caption)
            }.buttonStyle(.plain).foregroundStyle(.orange)
                .disabled(stale).help("Перейти к месту диагностики в редакторе")
        }
    }

    private func output(_ title: LocalizedStringResource, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(PresentationLocale.resource(title)).font(.caption.monospaced()).foregroundStyle(.secondary)
            ScrollView([.horizontal, .vertical]) {
                Group {
                    if text.isEmpty { Text("(пусто)") }
                    else { Text(verbatim: text) }
                }.font(.system(size: model.document.preferences.codeSize, design: .monospaced))
                    .textSelection(.enabled).fixedSize(horizontal: true, vertical: true).padding(12)
            }.defaultScrollAnchor(.topLeading)
                .frame(height: CGFloat(min(10, max(2, text.split(separator: "\n", omittingEmptySubsequences: false).count))) *
                       (model.document.preferences.codeSize + 5) + 24)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder private func failureView(_ failure: ExecutionFailure) -> some View {
        Group {
            switch failure {
            case .invalidRequest: Text("Код или ввод превышает 64 КиБ, либо запрос имеет неподдерживаемый формат.")
            case .missingAssets: Text("В этой сборке нет полной среды C++. Используйте упакованное приложение codelib.")
            case .modifiedAssets: Text("Образы среды повреждены или изменены. Запуск заблокирован; пересоберите или восстановите приложение.")
            case .invalidHelper: Text("Подпись приложения или helper не прошла проверку. Запуск заблокирован.")
            case .unavailable: Text("Для этой среды нужны Apple silicon и доступная аппаратная виртуализация.")
            case .deadline: Text("Среда не ответила вовремя и была принудительно остановлена.")
            case .invalidResponse, .transportFailed: Text("Связь со средой прервана. Запуск не считается успешным; можно повторить.")
            case .launchFailed: Text("Не удалось запустить изолированную среду.")
            case .busy: Text("Дождитесь завершения предыдущего запуска.")
            }
        }.font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
    }
}
