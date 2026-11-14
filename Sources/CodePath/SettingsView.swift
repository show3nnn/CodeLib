import SwiftUI
import LearningCore
import AppKit

struct SettingsView: View {
    enum Pane: String, CaseIterable { case profile = "Профиль", appearance = "Оформление", data = "Данные" }
    @Bindable var model: AppModel
    @State var pane: Pane = .profile
    @State private var confirmReset = false
    @State private var confirmImport = false
    @Environment(\.openWindow) private var openWindow
    @State private var editProfile = false
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("CODELIB / НАСТРОЙКИ").font(.system(size: 10, weight: .bold)).tracking(1.6).foregroundStyle(.green)
                        Text("Ваше пространство").font(.system(size: 28, weight: .bold)).tracking(-0.7)
                    }
                    Spacer()
                    Image(systemName: "slider.horizontal.3").font(.title2).foregroundStyle(.secondary)
                }
                Picker("Раздел настроек", selection: $pane) {
                    ForEach(Pane.allCases, id: \.self) { pane in Text(pane.rawValue).tag(pane) }
                }.pickerStyle(.segmented).labelsHidden().controlSize(.large).accessibilityIdentifier("settings.pane")
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if model.hasUnsavedChanges || model.saveError != nil {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Изменения ещё не сохранены", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                                FailureText(failure: model.saveError, fallback: "Идёт запись на диск.")
                                HStack {
                                    Button("Повторить сохранение") { model.flush() }
                                    Button("Экспорт") { model.exportProgress() }
                                }
                            }
                        }
                    }
                    switch pane {
                    case .profile: profilePane
                    case .appearance: appearancePane
                    case .data: dataPane
                    }
                }.padding(24).frame(maxWidth: 820).frame(maxWidth: .infinity)
            }.id(pane)
            Divider()
            HStack {
                Label("Только на вашем Mac", systemImage: "lock.shield").foregroundStyle(.secondary)
                Spacer()
                ReleaseVersionLabel(release: model.appRelease).foregroundStyle(.secondary)
            }.font(.caption).padding(.horizontal, 24).padding(.vertical, 14)
        }
        .background(WorkspaceBackdrop())
        .frame(minWidth: 600, idealWidth: 720, minHeight: 560, idealHeight: 740)
        .sheet(isPresented: $editProfile) {
            EditProfileView(model: model, profile: model.document.profile ?? LocalProfile())
        }
        .disabled(model.storageError != nil)
        .confirmationDialog("Удалить весь учебный прогресс?", isPresented: $confirmReset) {
            Button("Сбросить прогресс", role: .destructive) { model.reset() }
        } message: { Text("Ответы, черновики и настройки будут сброшены. Рекомендуем сначала экспортировать данные.") }
        .confirmationDialog("Заменить текущий прогресс импортируемым файлом?", isPresented: $confirmImport) {
            Button("Выбрать файл и заменить") { model.importProgress() }
        } message: { Text("Текущая сохранённая версия останется в резервной копии. Несовместимый файл не будет импортирован.") }
    }

    private var profilePane: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let profile = model.document.profile {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 20) {
                        ProfileAvatar(profile: profile, size: 76)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(profile.nickname).font(.system(size: 28, weight: .semibold)).tracking(-0.5)
                                .foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                            Label("Локальный профиль", systemImage: "internaldrive").font(.caption).foregroundStyle(.white.opacity(0.65))
                        }
                        Spacer(minLength: 0)
                    }
                    if let date = profile.createdAt {
                        Text("С вами с \(PresentationLocale.date(date))").font(.callout).foregroundStyle(.white.opacity(0.65))
                    }
                    Button { editProfile = true } label: {
                        Label("Редактировать профиль", systemImage: "pencil").font(.callout.weight(.medium))
                            .foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 11)
                            .background(.white.opacity(0.1), in: Capsule())
                            .overlay { Capsule().strokeBorder(.white.opacity(0.15)) }
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("settings.edit-profile")
                }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 0.055, green: 0.085, blue: 0.075), in: RoundedRectangle(cornerRadius: 24))
            } else {
                Card { Text("Профиль можно создать в главном окне начальной настройки.") }
            }
            if let course = model.course {
                HStack(spacing: 14) {
                    Metric(value: "\(model.document.completedCount(in: course))", label: "заданий завершено", icon: "checkmark.circle")
                    Metric(value: "\(AchievementCatalog.all.filter { model.document.achievements?.awards[$0.id] != nil }.count)", label: "достижений", icon: "trophy")
                }
                HStack {
                    Button("Мой прогресс", systemImage: "chart.bar") { showMain(.progress) }
                    Button("Коллекция наград", systemImage: "trophy") { showMain(.achievements) }
                }.buttonStyle(.bordered).controlSize(.large)
            }
            Text("Без регистрации и облачного аккаунта. Имя, аватар и результаты хранятся локально и входят в экспорт прогресса.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var appearancePane: some View {
        VStack(alignment: .leading, spacing: 20) {
            Card {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Оформление", systemImage: "circle.lefthalf.filled").font(.headline)
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

    private var dataPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            Card {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Ваши данные под вашим контролем", systemImage: "externaldrive.badge.checkmark").font(.headline)
                    Text("Прогресс хранится только на этом Mac. Резервная копия содержит предыдущую успешно сохранённую версию.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(model.dataURL.path).font(.caption.monospaced()).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Экспорт прогресса", systemImage: "square.and.arrow.up") { model.exportProgress() }
                        Button("Импорт…", systemImage: "square.and.arrow.down") { confirmImport = true }
                    }.buttonStyle(.bordered).controlSize(.large)
                    Button("Показать в Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.dataURL])
                    }.disabled(!FileManager.default.fileExists(atPath: model.dataURL.path))
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Начать заново", systemImage: "arrow.counterclockwise").font(.headline)
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
                    Text("C++17 запускается офлайн в изолированной Linux-среде без доступа к файлам Mac. Кодовые задания проверяются на примерах из условия; AI-помощника нет.")
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
