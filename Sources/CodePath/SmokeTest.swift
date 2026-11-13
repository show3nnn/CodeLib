#if DEBUG
import AppKit
import LearningCore
import SwiftUI

/// Explicit developer launch mode; renders real AppKit/SwiftUI windows and exits.
@MainActor
enum SmokeTest {
    static func run(model: AppModel, directory: URL, reopen: Bool) async {
        var checks: [String] = []
        var failures: [String] = []
        func check(_ condition: Bool, _ name: String) {
            if condition { checks.append(name) } else { failures.append(name) }
        }
        func settle() async { try? await Task.sleep(for: .milliseconds(250)) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            check(model.contentError == nil, "Bundled course loads inside app bundle")
            check(model.storageError == nil, "Progress file opens")
            let release = try AppRelease(info: Bundle.main.infoDictionary ?? [:])
            check(model.appRelease?.version == release.version, "Runtime version uses packaged metadata")
            check(model.releaseHistory?.releases.first?.version == release.version, "Release notes match app version")
            check(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String == "codelib", "Public application name is codelib")
            let course = try Course.bundled()
            let first = course.exercises[0]
            model.update { $0.preferences.achievementSounds = false }
            check(AchievementCatalog.soundURL != nil, "Original achievement sound is bundled")
            check(!AchievementAudio.play(enabled: false), "Disabled achievement sound does not play")
            if reopen {
                check(model.document.profile?.nickname == "Ученик 🚀", "Profile restored in a new process")
                check(model.startupRoute == .workspace, "Completed setup does not repeat on relaunch")
                check(model.document.lastViewedRelease == release.version, "Viewed release restored in a new process")
                check(model.document.exercises[first.id]?.draft == first.starter + "// smoke: черновик 🚀\n", "Draft restored after process restart")
                check(model.document.exercises[first.id]?.completion == .selfReviewed, "Self-completion restored after restart")
                check(model.document.preferences.theme == "dark", "Theme restored after restart")
                model.resume()
                check(model.exercise?.id == model.document.lastExerciseID, "Resume restores last exercise")
                if ProcessInfo.processInfo.arguments.contains("--simulate-update") {
                    model.update { $0.lastViewedRelease = NumericVersion(rawValue: "0.1.1") }
                    await settle()
                    check(model.startupRoute == .releaseHistory, "Existing completed profile routes to updates")
                    check(NSApp.windows.contains(where: { $0.isVisible && $0.title == "История обновлений codelib" }), "Update history automatically opens after version change")
                    check(!model.takeUpdateHistoryPresentation(), "Automatic update presentation occurs once per process")
                    check(model.markReleaseViewed(release.version), "Automatic update can be acknowledged durably")
                }
            } else {
                guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else {
                    throw ContentError.invalid("Main window not found")
                }
                check(model.startupRoute == .onboarding, "Fresh installation starts with onboarding")
                try snapshot(window: window, to: directory.appendingPathComponent("onboarding-welcome.png"))
                var setup = OnboardingState()
                setup.step = .appearance
                setup.draft = LocalProfile(nickname: "Ученик 🚀", avatar: .leaf)
                check(model.saveOnboarding(setup), "Partial setup persists")
                await settle()
                check(model.saveOnboarding(setup, finish: true), "Setup completion persists")
                await settle()
                check(model.startupRoute == .workspace, "Fresh install enters learning without update history")
                let previouslyViewed = model.document.lastViewedRelease
                check(!window.title.contains("CodePath"), "Main window has no legacy public title")
                check(activateMenuItem("О codelib", in: NSApp.mainMenu), "About menu entry is wired")
                await settle()
                if let about = NSApp.windows.first(where: { $0.isVisible && $0.title == "О codelib" }) {
                    try snapshot(window: about, to: directory.appendingPathComponent("about.png"))
                    check(about.contentView != nil, "Real About scene opens")
                    about.close()
                } else { failures.append("Real About scene opens") }
                check(activateMenuItem("История обновлений", in: NSApp.mainMenu), "History menu entry is wired")
                await settle()
                if let history = NSApp.windows.first(where: { $0.isVisible && $0.title == "История обновлений codelib" }) {
                    check(history.contentView != nil, "Real history scene opens")
                    for theme in ["light", "dark"] {
                        model.update { $0.preferences.theme = theme }
                        history.setContentSize(NSSize(width: theme == "light" ? 680 : 560, height: 580))
                        await settle()
                        try snapshot(window: history, to: directory.appendingPathComponent("history-\(theme).png"))
                    }
                    history.close()
                } else { failures.append("Real history scene opens") }
                check(model.document.lastViewedRelease == previouslyViewed, "Closing history does not change acknowledgement")
                check(model.markReleaseViewed(release.version), "Viewed release successfully saved")
                model.update { $0.preferences.theme = "light" }
                window.setContentSize(NSSize(width: 1180, height: 800))
                for page in [AppModel.Page.home, .catalog, .syllabus, .progress, .achievements] {
                    model.page = page
                    await settle()
                    try snapshot(window: window, to: directory.appendingPathComponent("\(page.rawValue)-light.png"))
                    check(window.contentView != nil, "Rendered page: \(page.rawValue)")
                }
                model.open(first)
                await settle()
                if let editor = findEditor(in: window.contentView) {
                    window.makeFirstResponder(editor)
                    let original = editor.string
                    let selection = editor.selectedRange()
                    let ruler = editor.enclosingScrollView?.verticalRulerView as? LineNumberRuler
                    check(ruler?.lines.count == SourceLines(original).count, "Logical line gutter matches source")
                    let directiveColor = editor.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil) as? NSColor
                    check(directiveColor == SyntaxColors.color(for: .directive), "Directive receives temporary syntax color")
                    model.update { $0.preferences.syntaxHighlighting = false; $0.preferences.showLineNumbers = false }
                    await settle()
                    check(editor.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil) == nil, "Highlighting can be disabled")
                    check(editor.enclosingScrollView?.rulersVisible == false, "Line numbers can be hidden")
                    check(editor.string == original && editor.selectedRange() == selection, "Presentation settings do not change source or selection")
                    model.update { $0.preferences.syntaxHighlighting = true; $0.preferences.showLineNumbers = true }
                    await settle()
                    check(editor.enclosingScrollView?.rulersVisible == true, "Line numbers can be restored")
                    if let scroll = editor.enclosingScrollView {
                        try snapshot(view: scroll, to: directory.appendingPathComponent("editor-light.png"))
                    }
                    check(ruler?.visibleLineRange() == 0...(SourceLines(original).count - 1), "Gutter draws all visible logical lines, not just the first two")
                    editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
                    editor.insertText("// smoke: черновик 🚀\n", replacementRange: editor.selectedRange())
                    await settle()
                    check(model.state(for: first.id).draft == first.starter + "// smoke: черновик 🚀\n", "AppKit editor updates saved draft")
                    editor.setSelectedRange(NSRange(location: 0, length: 0))
                    editor.insertTab(nil)
                    check(editor.string.hasPrefix("    #include"), "Real editor Tab")
                    await settle()
                    // Programmatic edits share one synthetic event; isolate the action under test.
                    editor.undoManager?.removeAllActions()
                    editor.insertBacktab(nil)
                    check(editor.string.hasPrefix("#include"), "Real editor Shift+Tab")
                    await settle()
                    check(!editor.isAutomaticQuoteSubstitutionEnabled, "Smart quotes disabled")
                    editor.undoManager?.undo()
                    await settle()
                    check(editor.string.hasPrefix("    #include"), "Indentation undo")
                    editor.undoManager?.redo()
                    await settle()
                } else { failures.append("AppKit editor is present") }
                model.selfComplete()
                check(model.state(for: first.id).completion == .selfReviewed, "Code is self-reviewed, not auto-graded")
                check(!model.hasUnsavedChanges, "Editor draft persisted to disk")
                check(model.document.achievements?.awards["award.selfreview"] != nil, "Real self-review unlocks its own achievement, not a run achievement")
                try snapshot(window: window, to: directory.appendingPathComponent("lesson-light.png"))

                for task in course.exercises where task.kind != .code {
                    model.open(task)
                    model.updateState(task.id) { $0.answer = "wrong" }
                    model.check()
                    check(model.state(for: task.id).lastCorrect == false, "Reject wrong answer: \(task.id)")
                    model.updateState(task.id) { $0.answer = task.answer! }
                    model.check()
                    check(model.state(for: task.id).completion == .automatic, "Accept correct answer: \(task.id)")
                }
                for lesson in course.lessons {
                    model.open(lesson.exercises[0])
                    await settle()
                    check(model.lesson?.id == lesson.id && findEditor(in: window.contentView) != nil, "Render lesson and editor: \(lesson.id)")
                }
                model.open(first)
                let originalDraft = model.state(for: first.id).draft
                let longDraft = String(repeating: "// Длинный черновик 🚀 для проверки прокрутки\n", count: 1000)
                model.updateState(first.id) { $0.draft = longDraft }
                await settle()
                check(findEditor(in: window.contentView)?.string == longDraft, "Large Unicode code draft renders without truncating stored text")
                check((findEditor(in: window.contentView)?.enclosingScrollView?.verticalRulerView as? LineNumberRuler)?.lines.count == 1001,
                      "Gutter updates for a thousand lines and trailing newline")
                model.updateState(first.id) { $0.draft = originalDraft }
                model.updateState(first.id) { $0.hintLevel = 3 }
                model.update { $0.preferences.theme = "dark"; $0.preferences.textSize = 22; $0.preferences.codeSize = 20 }
                window.setContentSize(NSSize(width: 760, height: 620))
                await settle()
                try snapshot(window: window, to: directory.appendingPathComponent("lesson-compact-dark.png"))
                if let editor = findEditor(in: window.contentView), let scroll = editor.enclosingScrollView {
                    let color = editor.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil) as? NSColor
                    check(color == SyntaxColors.color(for: .directive), "Highlighting survives font and theme changes")
                    try snapshot(view: scroll, to: directory.appendingPathComponent("editor-dark.png"))
                }
                check(window.contentLayoutRect.width >= 750, "Compact layout renders")
                let settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 570, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
                settings.contentView = NSHostingView(rootView: SettingsView(model: model).preferredColorScheme(.dark))
                settings.orderFront(nil)
                await settle()
                try snapshot(window: settings, to: directory.appendingPathComponent("settings-dark.png"))
                settings.orderOut(nil)
                let restored = try ProgressStore(url: model.dataURL)
                check(restored.document.exercises[first.id]?.draft == first.starter + "// smoke: черновик 🚀\n", "A new store reads actual editor text")
                check(restored.document.lastExerciseID == first.id, "Last exercise is durable")
                model.openLesson(course.lessons[0])
                check(model.exercise?.id == first.id, "Opening a lesson keeps its saved exercise")
                check(course.studySections(query: "вместимость рейса", status: .all, progress: model.document).flatMap(\.lessons).contains(where: { $0.id == "cpp.binarylab" }), "Syllabus search finds exercise titles")
                model.page = .syllabus
                await settle()
                try snapshot(window: window, to: directory.appendingPathComponent("syllabus-filters-dark.png"))
                check(window.contentView != nil, "Syllabus with status filters renders")
                model.open(first)
            }
        } catch { failures.append(error.localizedDescription) }
        let report: [String: Any] = ["checks": checks, "failures": failures, "reopen": reopen]
        do {
            let bytes = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            let name = ProcessInfo.processInfo.arguments.contains("--simulate-update") ? "update-report.json" : reopen ? "reopen-report.json" : "report.json"
            try bytes.write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch { failures.append(error.localizedDescription) }
        print("UI smoke: \(checks.count) checks; failures: \(failures)")
        // This mode is a test process, not a normal application exit.
        exit(failures.isEmpty ? 0 : 1)
    }

    private static func findEditor(in view: NSView?) -> EditingTextView? {
        guard let view else { return nil }
        if let editor = view as? EditingTextView { return editor }
        for child in view.subviews {
            if let editor = findEditor(in: child) { return editor }
        }
        return nil
    }

    private static func activateMenuItem(_ title: String, in menu: NSMenu?) -> Bool {
        guard let menu else { return false }
        for (index, item) in menu.items.enumerated() {
            if item.title == title && item.isEnabled {
                menu.performActionForItem(at: index)
                return true
            }
            if activateMenuItem(title, in: item.submenu) { return true }
        }
        return false
    }

    private static func snapshot(window: NSWindow, to url: URL) throws {
        guard let view = window.contentView else { throw ContentError.invalid("Window content missing") }
        try snapshot(view: view, to: url)
    }

    private static func snapshot(view: NSView, to url: URL) throws {
        guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw ContentError.invalid("Cannot create screenshot")
        }
        view.cacheDisplay(in: view.bounds, to: image)
        guard let data = image.representation(using: .png, properties: [:]) else {
            throw ContentError.invalid("Cannot encode screenshot")
        }
        try data.write(to: url)
    }
}
#endif
