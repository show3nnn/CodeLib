import ExecutionSupport
import SwiftUI

struct ExecutionConsoleView: View {
    @Bindable var model: AppModel
    let exerciseID: String
    let source: String
    let initialInput: String
    let navigate: (CompilerDiagnostic) -> Void
    private var input: Binding<String> {
        Binding(get: { model.execution.inputs[exerciseID] ?? initialInput },
                set: { model.execution.inputs[exerciseID] = $0 })
    }
    private var execution: CodeExecutionController { model.execution }
    private var isCurrent: Bool { execution.exerciseID == exerciseID }
    private var result: ExecutionResult? { isCurrent ? execution.result : nil }
    private var stale: Bool { isCurrent && (source != execution.sourceSnapshot || input.wrappedValue != execution.inputSnapshot) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Консоль C++", systemImage: "terminal").font(.headline)
                Spacer()
                if execution.isBusy {
                    Button("Остановить", systemImage: "stop.fill") { execution.cancel() }
                        .buttonStyle(.bordered).disabled(execution.state == .stopping)
                        .accessibilityIdentifier("execution.stop")
                } else {
                    Button("Запустить", systemImage: "play.fill") { model.runCode(stdin: input.wrappedValue) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("execution.run")
                }
            }
            Text("Ввод stdin · передаётся целиком перед запуском")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: input).font(.system(size: model.document.preferences.codeSize, design: .monospaced))
                .frame(height: 80).padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.1)) }
                .accessibilityLabel("Входные данные программы").accessibilityIdentifier("execution.stdin")
                // Never truncate user input. Oversized requests fail before VM launch.
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
                        ForEach(Array(CompilerDiagnostic.parse(result.stderr).enumerated()), id: \.offset) { _, item in
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
                    output("stdout", text: result.stdout)
                    if !result.stderr.isEmpty { output("stderr · диагностика", text: result.stderr) }
                    if result.status == .backendError && !result.detail.isEmpty {
                        DisclosureGroup("Технические сведения") {
                            Text(verbatim: result.detail).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                }
            } else {
                Text("C++17 · Linux / GCC · без сети и доступа к файлам Mac")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Успешный запуск не означает, что задача решена верно. Автопроверка кода пока не включена. Файлы программы исчезают после запуска.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.course?.exercises.first(where: { $0.id == exerciseID })?.testCases.contains(where: { $0.files?.isEmpty == false }) == true {
                Text("Сейчас передаётся только stdin. Файловые примеры не загружаются; файлы Mac недоступны.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(20)
            .background(.background, in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.1)) }
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
                    if let result {
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
        }.accessibilityElement(children: .combine).accessibilityAddTraits(.updatesFrequently)
    }

    private func output(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title).font(.caption.monospaced()).foregroundStyle(.secondary)
            ScrollView([.horizontal, .vertical]) {
                Text(verbatim: text.isEmpty ? "(пусто)" : text)
                    .font(.system(size: model.document.preferences.codeSize, design: .monospaced))
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
