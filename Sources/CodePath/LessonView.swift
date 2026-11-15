import SwiftUI
import AppKit
import LearningCore
import ExecutionSupport

// Display labels are UI resources, never persisted grading values or core dependencies.
extension ExerciseKind {
    var localizedTitle: LocalizedStringResource {
        let result: LocalizedStringResource = switch self {
        case .code: "Написать код"
        case .choice: "Выбрать объяснение"
        case .output: "Предсказать вывод"
        case .number: "Числовой ответ"
        case .text: "Короткий ответ"
        }
        return PresentationLocale.resource(result)
    }
}

extension Completion {
    var localizedTitle: LocalizedStringResource {
        let result: LocalizedStringResource = switch self {
        case .unfinished: "Не завершено"
        case .automatic: "Проверено автоматически"
        case .selfReviewed: "Отмечено вами"
        }
        return PresentationLocale.resource(result)
    }
}

struct LessonView: View {
    @Bindable var model: AppModel
    @State var showTheory = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let lesson = model.lesson, let exercise = model.exercise {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(lesson.title).font(.system(size: 19, weight: .semibold)).tracking(-0.3)
                        Text(PluralPresentation.taskProgress(lesson.exercises.filter { model.document.completed($0.id) }.count,
                                                             total: lesson.exercises.count, completed: true, locale: model.presentationLocale))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(showTheory ? "Скрыть теорию" : "Теория", systemImage: "book.closed") { showTheory.toggle() }
                        .buttonStyle(.bordered).tint(showTheory ? .green : .secondary)
                        .accessibilityIdentifier("lesson.theory")
                }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 16)
                ScrollViewReader { taskProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(lesson.exercises.enumerated()), id: \.element.id) { index, task in
                            Button {
                                model.open(task)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(String(format: "%02d", index + 1)).monospacedDigit()
                                    if task.id == exercise.id { Text(task.title).lineLimit(1) }
                                    if model.document.completed(task.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                                }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 10)
                                    .foregroundStyle(task.id == exercise.id ? Color.primary : .secondary)
                                    .background(task.id == exercise.id ? Color.green.opacity(0.12) : Color.primary.opacity(0.035), in: Capsule())
                                    .overlay { Capsule().strokeBorder(task.id == exercise.id ? Color.green.opacity(0.35) : .clear) }
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain).help(task.title)
                            .accessibilityLabel("Задание \(index + 1): \(task.title)")
                            .accessibilityAddTraits(task.id == exercise.id ? .isSelected : [])
                            .id(task.id)
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 16)
                }
                .onAppear { taskProxy.scrollTo(exercise.id, anchor: .center) }
                .onChange(of: exercise.id) { _, id in taskProxy.scrollTo(id, anchor: .center) }
                }
                Divider()
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 24) {
                                    Color.clear.frame(height: 0).id("top")
                                    ExerciseView(model: model, exercise: exercise, revealEditor: {
                                        proxy.scrollTo("editor-\(exercise.id)", anchor: .top)
                                    }).id(exercise.id)
                                }.padding(24).frame(maxWidth: 980).frame(maxWidth: .infinity)
                            }
                            .onChange(of: exercise.id) { _, _ in proxy.scrollTo("top", anchor: .top) }
                        }.frame(minWidth: 0, maxWidth: .infinity)
                        if showTheory && geometry.size.width >= 850 {
                            Divider()
                            ScrollView {
                                TheoryView(lesson: lesson, preferences: model.document.preferences).padding(24)
                            }.frame(width: 310).background(.background)
                        }
                    }.animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: showTheory)
                    .sheet(isPresented: Binding(get: { showTheory && geometry.size.width < 850 },
                                                set: { if !$0 { showTheory = false } })) {
                        VStack(spacing: 0) {
                            HStack {
                                Text(lesson.title).font(.headline)
                                Spacer()
                                Button("К заданию", systemImage: "xmark") { showTheory = false }
                            }.padding(20)
                            Divider()
                            ScrollView {
                                TheoryView(lesson: lesson, preferences: model.document.preferences).padding(24)
                            }
                        }.frame(minWidth: 440, idealWidth: 560, minHeight: 420, idealHeight: 620)
                    }
                }
                Divider()
                HStack {
                    Button("Назад", systemImage: "chevron.left") { model.move(-1) }
                        .buttonStyle(.bordered)
                        .disabled(model.course?.adjacent(to: exercise.id, offset: -1) == nil)
                    Spacer()
                    Label(model.hasUnsavedChanges ? "Не сохранено" : "Сохранено локально", systemImage: model.hasUnsavedChanges ? "exclamationmark.triangle" : "internaldrive")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Далее", systemImage: "chevron.right") { model.move(1) }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.course?.adjacent(to: exercise.id, offset: 1) == nil)
                }.controlSize(.large).padding(.horizontal, 24).padding(.vertical, 12).background(.bar)
            }
        } else {
            ContentUnavailableView {
                Label("Выберите урок", systemImage: "book")
            } description: {
                Text("Откройте программу курса или продолжите с последнего места.")
            } actions: {
                Button("Продолжить обучение") { model.resume() }.buttonStyle(.borderedProminent)
                Button("Программа курса") { model.page = .syllabus }
            }
        }
    }
}

private struct TheoryView: View {
    let lesson: Lesson
    let preferences: Preferences
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Теория", systemImage: "book.closed").font(.caption.weight(.semibold)).foregroundStyle(.green)
            Text("Коротко о главном").font(.system(size: 24, weight: .bold)).tracking(-0.6)
            Text(lesson.theory).font(.system(size: preferences.textSize)).lineSpacing(5).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            CodeBlock(code: lesson.example, fontSize: preferences.codeSize)
            DisclosureGroup {
                Text(lesson.microscope).font(.system(size: preferences.textSize)).lineSpacing(4)
                    .textSelection(.enabled).padding(.top, 10)
            } label: { Label("C++ под микроскопом", systemImage: "magnifyingglass").font(.headline) }
            Text(lesson.recap).font(.system(size: preferences.textSize)).foregroundStyle(.secondary)
        }
    }
}

struct ExerciseView: View {
    @Bindable var model: AppModel
    let exercise: Exercise
    let revealEditor: () -> Void
    @State private var showRepeatConfirmation = false
    @State private var showResetCodeConfirmation = false
    @State private var editorNavigation: EditorNavigation?
    private var state: ExerciseProgress { model.state(for: exercise.id) }
    private var draft: Binding<String> {
        Binding(get: { state.draft ?? exercise.starter }, set: { value in
            model.updateState(exercise.id) { $0.draft = value }
        })
    }
    private var answer: Binding<String> {
        Binding(get: { state.answer }, set: { value in
            model.updateState(exercise.id) { $0.answer = value; $0.lastCorrect = nil }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(PresentationLocale.resource(exercise.kind.localizedTitle, locale: model.presentationLocale)).textCase(.uppercase).font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(.green)
                        Spacer()
                        HStack(spacing: 4) {
                            ForEach(1...3, id: \.self) { level in
                                Capsule().fill(level <= exercise.difficulty ? Color.green : Color.primary.opacity(0.1))
                                    .frame(width: 12, height: 4)
                            }
                        }.accessibilityLabel("Сложность \(exercise.difficulty) из 3")
                    }
                    Text(exercise.title).font(.system(size: 28, weight: .bold)).tracking(-0.7)
                    Text(exercise.prompt).font(.system(size: model.document.preferences.textSize))
                        .lineSpacing(4).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !exercise.testCases.isEmpty && exercise.kind == .code {
                DisclosureGroup("Примеры входа и выхода") {
                    ForEach(Array(exercise.testCases.enumerated()), id: \.offset) { index, test in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Пример \(index + 1) · ввод").font(.caption).foregroundStyle(.secondary)
                            CodeBlock(code: test.input.isEmpty ? "(ввода нет)" : test.input, fontSize: model.document.preferences.codeSize)
                            Text("Вывод").font(.caption).foregroundStyle(.secondary)
                            CodeBlock(code: test.output, fontSize: model.document.preferences.codeSize)
                            if let files = test.files {
                                ForEach(files.keys.sorted(), id: \.self) { name in
                                    Text("Исходный файл: \(name)").font(.caption).foregroundStyle(.secondary)
                                    CodeBlock(code: files[name] ?? "", fontSize: model.document.preferences.codeSize)
                                }
                            }
                            if let files = test.expectedFiles {
                                ForEach(files.keys.sorted(), id: \.self) { name in
                                    Text("Ожидаемый файл: \(name)").font(.caption).foregroundStyle(.secondary)
                                    CodeBlock(code: files[name] ?? "", fontSize: model.document.preferences.codeSize)
                                }
                            }
                        }.padding(.top, 10)
                    }
                }
            }
            responseArea
            completionArea.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(.green.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Сначала попробуйте самостоятельно", systemImage: "lightbulb").font(.headline)
                    if state.hintLevel >= 1 {
                        Text("Намёк").font(.subheadline.bold())
                        Text(exercise.hints[0])
                    }
                    if state.hintLevel >= 2 {
                        Text("Подсказка").font(.subheadline.bold())
                        Text(exercise.hints[1])
                    }
                    if state.hintLevel < 2 {
                        Button(state.hintLevel == 0 ? "Нужен намёк" : "Раскрыть подсказку") {
                            model.updateState(exercise.id) { $0.hintLevel += 1 }
                        }
                    }
                    if state.hintLevel < 3 {
                        Button("Открыть разбор и ответ") { model.updateState(exercise.id) { $0.hintLevel = 3 } }
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Разбор").font(.headline)
                        Text(exercise.explanation).textSelection(.enabled)
                        if exercise.kind == .code {
                            CodeBlock(code: exercise.solution, fontSize: model.document.preferences.codeSize)
                        } else { Text("Ответ: \(exercise.answerLabel ?? "")").font(.system(.body, design: .monospaced)).textSelection(.enabled) }
                    }
                }.font(.system(size: model.document.preferences.textSize))
            }
        }
        .confirmationDialog("Повторить задание?", isPresented: $showRepeatConfirmation) {
            Button("Снять отметку выполнения") {
                model.updateState(exercise.id) { $0.completion = .unfinished; $0.lastCorrect = nil }
            }
        } message: { Text("Черновик, ответы и история подсказок останутся. Вы сможете заново завершить задание.") }
        .confirmationDialog("Заменить черновик стартовым кодом?", isPresented: $showResetCodeConfirmation) {
            Button("Сбросить код", role: .destructive) { model.resetCodeDraft() }
        } message: { Text("Текущий черновик будет заменён. Прежняя самостоятельная отметка и подсказки сохранятся; это не проверка нового текста.") }
    }

    @ViewBuilder var responseArea: some View {
        if exercise.kind == .code {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Label("main.cpp", systemImage: "curlybraces").font(.system(size: 12, weight: .medium, design: .monospaced))
                        Spacer(minLength: 0)
                        if model.execution.isBusy {
                            Button("Стоп", systemImage: "stop.fill") { model.execution.cancel() }
                                .keyboardShortcut(".", modifiers: .command).disabled(model.execution.state == .stopping)
                                .accessibilityIdentifier("editor.stop")
                        } else {
                            Button("Запустить", systemImage: "play.fill") {
                                model.runCode(stdin: model.execution.inputs[exercise.id] ?? exercise.testCases.first?.input ?? "")
                            }.buttonStyle(.borderedProminent).keyboardShortcut("r", modifiers: .command)
                                .accessibilityIdentifier("editor.run")
                        }
                        Button("Сбросить", systemImage: "arrow.counterclockwise") { showResetCodeConfirmation = true }
                            .labelStyle(.iconOnly).disabled(draft.wrappedValue == exercise.starter).help("Вернуть стартовый код с подтверждением")
                        Button("Копировать", systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(draft.wrappedValue, forType: .string)
                        }
                        .labelStyle(.iconOnly)
                    }.buttonStyle(.borderless).controlSize(.small).padding(14).background(.primary.opacity(0.035))
                    Divider()
                    CodeEditor(text: draft, fontSize: model.document.preferences.codeSize,
                                syntaxHighlighting: model.document.preferences.syntaxHighlighting,
                                showLineNumbers: model.document.preferences.showLineNumbers,
                                navigation: editorNavigation)
                        .frame(minHeight: 320, idealHeight: 400)
                        .accessibilityIdentifier("lesson.editor")
                    Divider()
                    ExecutionOutputView(model: model, exerciseID: exercise.id, source: draft.wrappedValue,
                                        initialInput: exercise.testCases.first?.input ?? "") { diagnostic in
                        revealEditor()
                        editorNavigation = EditorNavigation(source: model.execution.sourceSnapshot,
                                                            line: diagnostic.line, byteColumn: diagnostic.column)
                    }
                    Divider()
                    HStack {
                        Text("C++17").font(.system(.caption, design: .monospaced))
                        Spacer()
                        Label("Изолированный запуск · Linux / GCC", systemImage: "lock.shield")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary).padding(.horizontal, 14).padding(.vertical, 10)
                }.background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.1)) }
                    .id("editor-\(exercise.id)")
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("lesson.code-workspace")
                Text("Tab / Shift+Tab — отступы · Control+Tab — выйти из редактора · Enter сохраняет отступ")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            if !exercise.starter.isEmpty { CodeBlock(code: exercise.starter, fontSize: model.document.preferences.codeSize) }
            if exercise.kind == .choice {
                Picker("Ваш ответ", selection: answer) {
                    Text("Выберите вариант").tag("")
                    ForEach(exercise.choices, id: \.self) { Text(exercise.choiceLabel(for: $0)).tag($0) }
                }.pickerStyle(.radioGroup)
            } else if exercise.kind == .output {
                Text("Ваш прогноз вывода").font(.headline)
                TextEditor(text: answer).font(.system(size: model.document.preferences.codeSize, design: .monospaced))
                    .frame(height: 110).border(.secondary.opacity(0.3))
                    .accessibilityLabel("Прогноз вывода программы")
            } else {
                TextField("Ваш ответ", text: answer).textFieldStyle(.roundedBorder)
            }
        }
    }

    private var completionArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if exercise.kind == .code {
                    if exercise.gradingFixtures != nil {
                        Button("Проверить решение", systemImage: "checkmark.seal") { model.gradeCode() }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.return, modifiers: [.command, .shift])
                            .disabled(model.execution.isBusy)
                        Button("Отметить самому") { model.selfComplete() }
                            .buttonStyle(.bordered)
                            .disabled(state.completion != .unfinished)
                            .help(state.completion == .automatic
                                  ? Text("Задание уже проверено на примерах")
                                  : Text("Отметить выполнение без автопроверки"))
                    } else {
                        Button("Отметить выполненным", systemImage: "checkmark") { model.selfComplete() }
                            .buttonStyle(.borderedProminent).disabled(state.completion == .selfReviewed)
                    }
                } else {
                    Button("Проверить ответ", systemImage: "checkmark.circle") { model.check() }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
                        .disabled(state.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if state.completion != .unfinished {
                    Spacer()
                    Button("Повторить") { showRepeatConfirmation = true }
                }
            }
            if exercise.kind == .code && state.completion == .unfinished {
                if exercise.gradingFixtures != nil {
                    Text("Проверка запускает примеры из условия в изолированной среде и сравнивает вывод. Задание засчитывается только при совпадении на каждом примере; запуск сам по себе ничего не засчитывает.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Самопроверка: сравните вывод с условием и разбором. Запуск программы не является автоматической проверкой решения.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if state.completion != .unfinished {
                Label { Text(PresentationLocale.resource(state.completion.localizedTitle, locale: model.presentationLocale)) } icon: {
                    Image(systemName: state.completion == .automatic ? "checkmark.seal.fill" : "person.crop.circle.badge.checkmark")
                }
                    .foregroundStyle(.green).font(.subheadline.weight(.medium))
                if state.completion == .automatic && state.lastCorrect != true {
                    Text("Задание завершено ранее. Текущий изменённый ответ ещё не подтверждён.").font(.caption).foregroundStyle(.secondary)
                }
                if exercise.kind == .code {
                    if state.completion == .automatic {
                        Text("Задание проверено на примерах из условия. Изменение кода не отменяет прежнюю отметку, но новый вывод нужно проверить отдельно.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Это ваша отметка, не автоматическая проверка. Изменения кода не перепроверяются.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let correct = state.lastCorrect {
                Label(correct ? "Верно. \(exercise.explanation)" : "Пока не совпало. Проверьте условие, формат и значения; можно раскрыть намёк.",
                      systemImage: correct ? "checkmark.circle" : "arrow.counterclockwise")
                    .foregroundStyle(correct ? Color.green : Color.orange)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if state.attempts > 0 { Text("Попыток: \(state.attempts)").font(.caption).foregroundStyle(.secondary) }
            if let lesson = model.lesson, model.document.lessonCompleted(lesson) {
                Label("Урок завершён. Отличная работа! Можно повторить материал или перейти дальше.", systemImage: "sparkles").foregroundStyle(.tint)
            }
        }
    }
}
