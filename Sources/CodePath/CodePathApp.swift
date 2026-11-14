import SwiftUI
import LearningCore
import AppKit

@main
struct CodePathApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("codelib", id: "main") {
            RootView(model: model)
                .environment(\.locale, PresentationLocale.locale)
                .tint(.green)
                .preferredColorScheme(model.colorScheme)
                .onAppear {
                    delegate.model = model
                    #if DEBUG
                    delegate.startSmokeTestIfRequested()
                    #endif
                }
        }
        .defaultSize(width: 1180, height: 800)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("О codelib") { openWindow(id: "about") }
                Button("История обновлений") { openWindow(id: "release-history") }
            }
            CommandGroup(after: .newItem) {
                Button("Продолжить обучение") { model.resume() }.keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandMenu("Обучение") {
                Button("Предыдущее задание") { model.move(-1) }.keyboardShortcut("[", modifiers: .command)
                    .disabled(model.page != .lesson || model.course?.adjacent(to: model.selectedExerciseID ?? "", offset: -1) == nil)
                Button("Следующее задание") { model.move(1) }.keyboardShortcut("]", modifiers: .command)
                    .disabled(model.page != .lesson || model.course?.adjacent(to: model.selectedExerciseID ?? "", offset: 1) == nil)
                Button("Сохранить изменения") { model.flush() }.keyboardShortcut("s", modifiers: .command)
            }
        }
        Settings {
            SettingsView(model: model).environment(\.locale, PresentationLocale.locale).preferredColorScheme(model.colorScheme).tint(.green)
        }
        Window("О codelib", id: "about") {
            AboutView(model: model).environment(\.locale, PresentationLocale.locale).preferredColorScheme(model.colorScheme).tint(.green)
        }.windowResizability(.contentSize)
        Window("История обновлений codelib", id: "release-history") {
            ReleaseHistoryView(model: model).environment(\.locale, PresentationLocale.locale).preferredColorScheme(model.colorScheme).tint(.green)
        }.defaultSize(width: 680, height: 720)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    #if DEBUG
    private var smokeStarted = false
    func startSmokeTestIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard !smokeStarted, let index = args.firstIndex(of: "--ui-smoke-test"),
              args.indices.contains(index + 1), let model else { return }
        smokeStarted = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            await SmokeTest.run(model: model, directory: URL(fileURLWithPath: args[index + 1]), reopen: args.contains("--reopen"))
        }
    }
    #endif
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.flush()
        guard model?.hasUnsavedChanges == true else { model?.execution.cancel(); return .terminateNow }
        let alert = Self.unsavedChangesAlert()
        if alert.runModal() == .alertSecondButtonReturn { model?.execution.cancel(); return .terminateNow }
        return .terminateCancel
    }

    static func unsavedChangesAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = String(localized: PresentationLocale.resource("Изменения не сохранены"))
        alert.informativeText = String(localized: PresentationLocale.resource("Не удалось записать прогресс. Останьтесь в приложении, чтобы повторить сохранение или экспортировать данные."))
        alert.addButton(withTitle: String(localized: PresentationLocale.resource("Остаться")))
        alert.addButton(withTitle: String(localized: PresentationLocale.resource("Выйти без сохранения")))
        return alert
    }
}
