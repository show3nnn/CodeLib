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
                .environment(\.locale, model.presentationLocale)
                .tint(.green)
                .preferredColorScheme(model.colorScheme)
                .onAppear {
                    delegate.model = model
                    #if DEBUG
                    delegate.startSmokeTestIfRequested()
                    delegate.startAcceptanceTestIfRequested()
                    #endif
                }
        }
        .defaultSize(width: 1180, height: 800)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button { openWindow(id: "about") } label: {
                    nativeTitle("О codelib", locale: model.presentationLocale)
                }
                Button { openWindow(id: "release-history") } label: {
                    nativeTitle("История обновлений", locale: model.presentationLocale)
                }
            }
            CommandGroup(after: .newItem) {
                Button { model.resume() } label: {
                    nativeTitle("Продолжить обучение", locale: model.presentationLocale)
                }.keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandMenu(nativeTitle("Обучение", locale: model.presentationLocale)) {
                Button { model.move(-1) } label: {
                    nativeTitle("Предыдущее задание", locale: model.presentationLocale)
                }.keyboardShortcut("[", modifiers: .command)
                    .disabled(model.page != .lesson || model.course?.adjacent(to: model.selectedExerciseID ?? "", offset: -1) == nil)
                Button { model.move(1) } label: {
                    nativeTitle("Следующее задание", locale: model.presentationLocale)
                }.keyboardShortcut("]", modifiers: .command)
                    .disabled(model.page != .lesson || model.course?.adjacent(to: model.selectedExerciseID ?? "", offset: 1) == nil)
                Button { model.flush() } label: {
                    nativeTitle("Сохранить изменения", locale: model.presentationLocale)
                }.keyboardShortcut("s", modifiers: .command)
            }
        }
        .environment(\.locale, model.presentationLocale)
        Settings {
            SettingsView(model: model).environment(\.locale, model.presentationLocale).preferredColorScheme(model.colorScheme).tint(.green)
        }
        Window(nativeTitle("О codelib", locale: model.presentationLocale), id: "about") {
            AboutView(model: model).environment(\.locale, model.presentationLocale).preferredColorScheme(model.colorScheme).tint(.green)
        }.windowResizability(.contentSize).environment(\.locale, model.presentationLocale)
        Window(nativeTitle("История обновлений codelib", locale: model.presentationLocale), id: "release-history") {
            ReleaseHistoryView(model: model).environment(\.locale, model.presentationLocale).preferredColorScheme(model.colorScheme).tint(.green)
        }.defaultSize(width: 680, height: 720).environment(\.locale, model.presentationLocale)
    }
}

/// Resolve only at the native scene/command presentation boundary.
private func nativeTitle(_ resource: LocalizedStringResource, locale: Locale) -> Text {
    Text(verbatim: String(localized: PresentationLocale.resource(resource, locale: locale)))
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    #if DEBUG
    private var smokeStarted = false
    private var acceptanceStarted = false
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
    func startAcceptanceTestIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard !acceptanceStarted, let index = args.firstIndex(of: "--acceptance-run"),
              args.indices.contains(index + 1), let model else { return }
        acceptanceStarted = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            await AcceptanceTest.run(model: model, directory: URL(fileURLWithPath: args[index + 1]))
        }
    }
    #endif
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.flush()
        guard model?.hasUnsavedChanges == true else { model?.execution.cancel(); return .terminateNow }
        let alert = Self.unsavedChangesAlert(locale: model?.presentationLocale ?? PresentationLocale.locale)
        if alert.runModal() == .alertSecondButtonReturn { model?.execution.cancel(); return .terminateNow }
        return .terminateCancel
    }

    static func unsavedChangesAlert(locale: Locale = PresentationLocale.locale) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = String(localized: PresentationLocale.resource("Изменения не сохранены", locale: locale))
        alert.informativeText = String(localized: PresentationLocale.resource("Не удалось записать прогресс. Останьтесь в приложении, чтобы повторить сохранение или экспортировать данные.", locale: locale))
        alert.addButton(withTitle: String(localized: PresentationLocale.resource("Остаться", locale: locale)))
        alert.addButton(withTitle: String(localized: PresentationLocale.resource("Выйти без сохранения", locale: locale)))
        return alert
    }
}
