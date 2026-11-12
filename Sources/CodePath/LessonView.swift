import SwiftUI
import AppKit
import LearningCore

struct LessonView: View {
    @Bindable var model: AppModel
    @State private var showTheory = true

    var body: some View {
        if let lesson = model.lesson, let exercise = model.exercise {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(lesson.title).font(.headline)
                        Text("\(lesson.exercises.filter { model.document.completed($0.id) }.count) из \(lesson.exercises.count) заданий завершено")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(showTheory ? "Скрыть теорию" : "Теория", systemImage: "book") { showTheory.toggle() }
                }.padding()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(lesson.exercises.enumerated()), id: \.element.id) { index, task in
                            Button {
                                model.open(task)
                            } label: {
                                HStack(spacing: 5) {
                                    if model.document.completed(task.id) { Image(systemName: "checkmark") }
                                    Text("\(index + 1). \(task.title)")
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(task.id == exercise.id ? .accentColor : .secondary)
                            .accessibilityAddTraits(task.id == exercise.id ? .isSelected : [])
                        }
                    }.padding(.horizontal).padding(.bottom, 12)
                }
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            Color.clear.frame(height: 0).id("top")
                            if showTheory {
                                TheoryView(lesson: lesson, preferences: model.document.preferences)
                            }
                            ExerciseView(model: model, exercise: exercise).id(exercise.id)
                        }.padding(24).frame(maxWidth: 1040).frame(maxWidth: .infinity)
                    }
                    .onChange(of: exercise.id) { _, _ in proxy.scrollTo("top", anchor: .top) }
                }
                Divider()
                HStack {
                    Button("Назад", systemImage: "chevron.left") { model.move(-1) }
                        .disabled(model.course?.adjacent(to: exercise.id, offset: -1) == nil)
                    Spacer()
                    Label(model.hasUnsavedChanges ? "Не сохранено" : "Сохранено локально", systemImage: model.hasUnsavedChanges ? "exclamationmark.triangle" : "internaldrive")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Далее", systemImage: "chevron.right") { model.move(1) }
                        .disabled(model.course?.adjacent(to: exercise.id, offset: 1) == nil)
                }.padding(14)
            }
        } else {
            ContentUnavailableView("Выберите урок", systemImage: "book", description: Text("Откройте программу курса или продолжите с последнего места."))
        }
    }
}

private struct TheoryView: View {
    let lesson: Lesson
    let preferences: Preferences
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Коротко о главном").font(.title2.bold())
            Text(lesson.theory).font(.system(size: preferences.textSize)).lineSpacing(5).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            CodeBlock(code: lesson.example, fontSize: preferences.codeSize)
            DisclosureGroup {
                Text(lesson.microscope).font(.system(size: preferences.textSize)).lineSpacing(4)
                    .textSelection(.enabled).padding(.top, 10)
            } label: { Label("C++ под микроскопом", systemImage: "magnifyingglass").font(.headline) }
            Text(lesson.recap).font(.system(size: preferences.textSize)).foregroundStyle(.secondary)
            Divider()
        }
    }
}

private struct ExerciseView: View {
    @Bindable var model: AppModel
    let exercise: Exercise
    @State private var showRepeatConfirmation = false
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
            HStack {
                Text(exercise.kind.title.uppercased()).font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.tint)
                Spacer()
                Text("Сложность \(exercise.difficulty)/3").font(.caption).foregroundStyle(.secondary)
            }
            Text(exercise.title).font(.title.bold())
            Text(exercise.prompt).font(.system(size: model.document.preferences.textSize)).lineSpacing(4).textSelection(.enabled)
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
            completionArea
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
                        } else { Text("Ответ: \(exercise.answer ?? "")").font(.system(.body, design: .monospaced)).textSelection(.enabled) }
                    }
                }.font(.system(size: model.document.preferences.textSize))
            }
        }
        .confirmationDialog("Повторить задание?", isPresented: $showRepeatConfirmation) {
            Button("Снять отметку выполнения") {
                model.updateState(exercise.id) { $0.completion = .unfinished; $0.lastCorrect = nil }
            }
        } message: { Text("Черновик, ответы и история подсказок останутся. Вы сможете заново завершить задание.") }
    }

    @ViewBuilder private var responseArea: some View {
        if exercise.kind == .code {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Ваш код · C++17").font(.headline)
                    Spacer()
                    Button("Копировать", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(draft.wrappedValue, forType: .string)
                    }
                }
                CodeEditor(text: draft, fontSize: model.document.preferences.codeSize,
                           syntaxHighlighting: model.document.preferences.syntaxHighlighting,
                           showLineNumbers: model.document.preferences.showLineNumbers)
                    .frame(minHeight: 300, idealHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.12)) }
                Text("Tab / Shift+Tab — отступы · Control+Tab — выйти из редактора · Enter сохраняет отступ · Длинные строки переносятся · Компилятора в этой версии нет")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            if !exercise.starter.isEmpty { CodeBlock(code: exercise.starter, fontSize: model.document.preferences.codeSize) }
            if exercise.kind == .choice {
                Picker("Ваш ответ", selection: answer) {
                    Text("Выберите вариант").tag("")
                    ForEach(exercise.choices, id: \.self) { Text($0).tag($0) }
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
                    Button("Я проверил(а) решение — отметить выполненным", systemImage: "checkmark") { model.selfComplete() }
                        .buttonStyle(.borderedProminent).disabled(state.completion == .selfReviewed)
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
            if state.completion != .unfinished {
                Label(state.completion.title, systemImage: state.completion == .automatic ? "checkmark.seal.fill" : "person.crop.circle.badge.checkmark")
                    .foregroundStyle(.green).font(.subheadline.weight(.medium))
                if state.completion == .automatic && state.lastCorrect != true {
                    Text("Задание завершено ранее. Текущий изменённый ответ ещё не подтверждён.").font(.caption).foregroundStyle(.secondary)
                }
                if exercise.kind == .code {
                    Text("Это ваша отметка, не автоматическая проверка. Изменения кода не перепроверяются.").font(.caption).foregroundStyle(.secondary)
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
