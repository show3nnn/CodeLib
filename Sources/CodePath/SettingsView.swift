import SwiftUI
import LearningCore
import AppKit

struct SettingsView: View {
    enum Section: String, CaseIterable {
        case profile = "Профиль", appearance = "Оформление", data = "Данные"
        var title: LocalizedStringResource {
            let title: LocalizedStringResource = switch self {
            case .profile: "Профиль"
            case .appearance: "Оформление"
            case .data: "Данные"
            }
            return PresentationLocale.resource(title)
        }
    }

    static let minimumSize = CGSize(width: 420, height: 500)
    static let defaultSize = CGSize(width: 460, height: 720)

    @Bindable var model: AppModel
    /// A starting scroll position for captures; the normal window starts at the top.
    var initialSection: Section? = nil
    @State private var confirmReset = false
    @State private var confirmImport = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editProfile = false
    var body: some View {
        ScrollViewReader { scroll in
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CODELIB / НАСТРОЙКИ").font(.system(size: 10, weight: .bold)).tracking(1.6).foregroundStyle(.green)
                        Text("Ваше пространство").font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)
                    }
                    Spacer(minLength: 0)
                    Menu {
                        ForEach(Section.allCases, id: \.self) { section in
                            Button {
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                    scroll.scrollTo(section, anchor: .top)
                                }
                            } label: { Text(PresentationLocale.resource(section.title, locale: model.presentationLocale)) }
                        }
                    } label: {
                        Label("Раздел настроек", systemImage: "list.bullet").labelStyle(.iconOnly)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Раздел настроек")
                    .accessibilityIdentifier("settings.section-menu")
                }
                .padding(12)
                .padding(.horizontal, 16).padding(.vertical, 10)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 16) {
                            if model.hasUnsavedChanges || model.saveError != nil {
                                Card {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Label("Изменения ещё не сохранены", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                                        FailureText(failure: model.saveError, fallback: "Идёт запись на диск.", locale: model.presentationLocale)
                                        HStack {
                                            Button("Повторить сохранение") { model.flush() }
                                            Button("Экспорт") { model.exportProgress() }
                                        }
                                    }
                                }
                            }
                            profileSection
                        }
                        .id(Section.profile)
                        appearanceSection.id(Section.appearance)
                        dataSection.id(Section.data)
                    }
                    .padding(16).frame(maxWidth: 540).frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("settings.sections")
                .onAppear {
                    if let initialSection { scroll.scrollTo(initialSection, anchor: .top) }
                }
                Divider()
                HStack {
                    Label("Только на вашем Mac", systemImage: "lock.shield").foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    ReleaseVersionLabel(release: model.appRelease).foregroundStyle(.secondary)
                }.font(.caption).padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .background(WorkspaceBackdrop())
        .frame(minWidth: Self.minimumSize.width, idealWidth: Self.defaultSize.width,
               minHeight: Self.minimumSize.height, idealHeight: Self.defaultSize.height)
        .sheet(isPresented: $editProfile) {
            EditProfileView(model: model, profile: model.document.profile ?? LocalProfile())
        }
        .disabled(model.storageError != nil)
        .onDisappear {
            if model.execution.readiness == .checking { model.execution.cancel() }
        }
        .confirmationDialog("Удалить весь учебный прогресс?", isPresented: $confirmReset) {
            Button("Сбросить прогресс", role: .destructive) { model.reset() }
        } message: { Text("Ответы, черновики и настройки будут сброшены. Рекомендуем сначала экспортировать данные.") }
        .confirmationDialog("Заменить текущий прогресс импортируемым файлом?", isPresented: $confirmImport) {
            Button("Выбрать файл и заменить") { model.importProgress() }
        } message: { Text("Текущая сохранённая версия останется в резервной копии. Несовместимый файл не будет импортирован.") }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let profile = model.document.profile {
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 16) {
                            ProfileAvatar(profile: profile, size: 56)
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Локальный профиль", systemImage: "internaldrive").font(.caption).foregroundStyle(.secondary)
                                Text(profile.nickname).font(.title3.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if let date = profile.createdAt {
                            Text("С вами с \(PresentationLocale.date(date, locale: model.presentationLocale))")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Button { editProfile = true } label: {
                            Label("Редактировать профиль", systemImage: "pencil")
                        }
                        .buttonStyle(.bordered).accessibilityIdentifier("settings.edit-profile")
                    }
                }
            } else {
                Card { Text("Профиль можно создать в главном окне начальной настройки.") }
            }
            if let course = model.course {
                let completed = model.document.completedCount(in: course)
                let awards = AchievementCatalog.all.filter { model.document.achievements?.awards[$0.id] != nil }.count
                HStack(spacing: 14) {
                    Metric(value: "\(completed)", label: PluralPresentation.metricLabel(.tasks, count: completed, locale: model.presentationLocale), icon: "checkmark.circle", locale: model.presentationLocale)
                    Metric(value: "\(awards)", label: PluralPresentation.metricLabel(.achievements, count: awards, locale: model.presentationLocale), icon: "trophy", locale: model.presentationLocale)
                }
                HStack {
                    Button("Мой прогресс", systemImage: "chart.bar") { showMain(.progress) }
                    Button("Коллекция наград", systemImage: "trophy") { showMain(.achievements) }
                }.buttonStyle(.bordered)
            }
            Text("Без регистрации и облачного аккаунта. Имя, аватар и результаты хранятся локально и входят в экспорт прогресса.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Оформление", systemImage: "circle.lefthalf.filled").font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Picker("Тема", selection: Binding(get: { model.document.preferences.theme }, set: { value in
                        model.update { $0.preferences.theme = value }
                    })) {
                        Text("Системная").tag("system")
                        Text("Светлая").tag("light")
                        Text("Тёмная").tag("dark")
                    }.pickerStyle(.segmented).labelsHidden()
                    Text("Применяется сразу ко всем окнам codelib.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 20) {
                    Label("Размер текста", systemImage: "textformat.size").font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    HStack {
                        Text("Теория и задания")
                        Spacer()
                        Text("\(Int(model.document.preferences.textSize)) пт").monospacedDigit().foregroundStyle(.secondary)
                        Button("Сбросить") { model.update { $0.preferences.textSize = Preferences().textSize } }
                            .buttonStyle(.borderless).controlSize(.small).accessibilityLabel("Сбросить размер текста курса")
                    }
                    Slider(value: Binding(get: { model.document.preferences.textSize }, set: { value in
                        model.update { $0.preferences.textSize = value }
                    }), in: 12...28, step: 1) { Text("Размер текста курса") }.labelsHidden()
                    Text("Учиться удобно, когда текст читается легко.")
                        .font(.system(size: model.document.preferences.textSize)).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    HStack {
                        Text("Редактор и примеры")
                        Spacer()
                        Text("\(Int(model.document.preferences.codeSize)) пт").monospacedDigit().foregroundStyle(.secondary)
                        Button("Сбросить") { model.update { $0.preferences.codeSize = Preferences().codeSize } }
                            .buttonStyle(.borderless).controlSize(.small).accessibilityLabel("Сбросить размер кода")
                    }
                    Slider(value: Binding(get: { model.document.preferences.codeSize }, set: { value in
                        model.update { $0.preferences.codeSize = value }
                    }), in: 11...26, step: 1) { Text("Размер кода") }.labelsHidden()
                    CodeBlock(code: "int answer = 42;\nstd::cout << answer;", fontSize: model.document.preferences.codeSize)
                    Button("Стандартные размеры шрифта", systemImage: "arrow.counterclockwise") { model.resetTypography() }
                        .buttonStyle(.bordered)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Редактор и уведомления", systemImage: "curlybraces").font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Toggle("Подсветка синтаксиса", isOn: Binding(get: { model.document.preferences.syntaxHighlighting }, set: { value in
                        model.update { $0.preferences.syntaxHighlighting = value }
                    }))
                    Toggle("Номера строк", isOn: Binding(get: { model.document.preferences.showLineNumbers }, set: { value in
                        model.update { $0.preferences.showLineNumbers = value }
                    }))
                    Divider()
                    Toggle("Звуки достижений", isOn: Binding(get: { model.document.preferences.achievementSounds }, set: { value in
                        model.update { $0.preferences.achievementSounds = value }
                    }))
                    Text("Подсветка не проверяет код. Громкость звука определяется macOS.")
                        .font(.caption).foregroundStyle(.secondary)
                }.toggleStyle(.switch)
            }
        }
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card {
                ExecutionReadinessView(execution: model.execution)
            }
            Card {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Ваши данные под вашим контролем", systemImage: "externaldrive.badge.checkmark").font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text("Прогресс хранится только на этом Mac. Резервная копия содержит предыдущую успешно сохранённую версию.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(model.dataURL.path).font(.caption.monospaced()).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Экспорт прогресса", systemImage: "square.and.arrow.up") { model.exportProgress() }
                        Button("Импорт…", systemImage: "square.and.arrow.down") { confirmImport = true }
                    }.buttonStyle(.bordered)
                    Button("Показать в Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.dataURL])
                    }.disabled(!FileManager.default.fileExists(atPath: model.dataURL.path))
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Начать заново", systemImage: "arrow.counterclockwise").font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text("Полный сброс удаляет профиль, ответы, черновики и настройки. Сначала сохраните экспорт.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Сбросить прогресс…", role: .destructive) { confirmReset = true }.buttonStyle(.bordered)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Text("codelib").font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Нативная лаборатория C++ · без аккаунтов, сети и телеметрии.").foregroundStyle(.secondary)
                    HStack {
                        Button("О codelib") { openWindow(id: "about") }
                        Button("История обновлений") { openWindow(id: "release-history") }
                    }.buttonStyle(.bordered)
                    Text("C++17 запускается офлайн в изолированной Linux-среде без доступа к файлам Mac. Кодовые задания с автопроверкой проверяются на примерах из условия; остальные кодовые задания — самостоятельно. AI-помощника нет.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func showMain(_ page: AppModel.Page) {
        model.page = page
        openWindow(id: "main")
    }
}
