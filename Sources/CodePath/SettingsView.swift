import SwiftUI
import LearningCore

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var confirmReset = false
    @State private var confirmImport = false
    @Environment(\.openWindow) private var openWindow
    @State private var editProfile = false
    var body: some View {
        Form {
            Section("Локальный профиль") {
                if let profile = model.document.profile {
                    HStack {
                        ProfileAvatar(profile: profile)
                        Text(profile.nickname).font(.headline)
                        Spacer()
                        Button("Изменить…") { editProfile = true }
                    }
                    if let date = profile.createdAt {
                        Text("Профиль создан: \(PresentationLocale.date(date))").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Дата создания прежнего профиля не была сохранена.").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Профиль можно создать в главном окне начальной настройки.")
                }
            }
            Section("Оформление") {
                Picker("Тема", selection: Binding(get: { model.document.preferences.theme }, set: { value in
                    model.update { $0.preferences.theme = value }
                })) {
                    Text("Системная").tag("system")
                    Text("Светлая").tag("light")
                    Text("Тёмная").tag("dark")
                }
                Slider(value: Binding(get: { model.document.preferences.textSize }, set: { value in
                    model.update { $0.preferences.textSize = value }
                }), in: 12...28, step: 1) {
                    Text("Текст: \(Int(model.document.preferences.textSize)) пт")
                }
                Slider(value: Binding(get: { model.document.preferences.codeSize }, set: { value in
                    model.update { $0.preferences.codeSize = value }
                }), in: 11...26, step: 1) {
                    Text("Код: \(Int(model.document.preferences.codeSize)) пт")
                }
                Text("Учиться удобно, когда текст читается легко.")
                    .font(.system(size: model.document.preferences.textSize))
                CodeBlock(code: "int answer = 42;\nstd::cout << answer;", fontSize: model.document.preferences.codeSize)
                Button("Стандартные размеры шрифта") {
                    model.resetTypography()
                }
            }
            Section("Редактор C++") {
                Toggle("Подсветка синтаксиса", isOn: Binding(get: { model.document.preferences.syntaxHighlighting }, set: { value in
                    model.update { $0.preferences.syntaxHighlighting = value }
                }))
                Toggle("Номера строк", isOn: Binding(get: { model.document.preferences.showLineNumbers }, set: { value in
                    model.update { $0.preferences.showLineNumbers = value }
                }))
                Text("Подсветка помогает читать код, но не проверяет его правильность и не запускает программу.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Уведомления") {
                Toggle("Звуки достижений", isOn: Binding(get: { model.document.preferences.achievementSounds }, set: { value in
                    model.update { $0.preferences.achievementSounds = value }
                }))
                Text("Короткий оригинальный звук при получении награды. Громкость зависит от macOS.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Локальные данные") {
                Text("Прогресс хранится только на этом Mac. Резервная копия содержит предыдущую успешно сохранённую версию.")
                    .foregroundStyle(.secondary)
                Text(model.dataURL.path).font(.caption).textSelection(.enabled)
                HStack {
                    Button("Экспорт прогресса") { model.exportProgress() }
                    Button("Импорт…") { confirmImport = true }
                }
                Button("Сбросить прогресс…", role: .destructive) { confirmReset = true }
            }
            Section("О codelib") {
                ReleaseVersionLabel(release: model.appRelease)
                HStack {
                    Button("О codelib") { openWindow(id: "about") }
                    Button("История обновлений") { openWindow(id: "release-history") }
                }
                Text("Нативная лаборатория C++ · без аккаунтов, сети и телеметрии.")
                Text("Написание кода проверяется самостоятельно. Встроенного исполнения кода и AI-помощника в этой версии нет.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).padding().frame(width: 570, height: 640)
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
}
