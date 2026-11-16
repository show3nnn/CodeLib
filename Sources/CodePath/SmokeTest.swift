#if DEBUG
import AppKit
import CoreGraphics
import Darwin
import LearningCore
import SwiftUI
import ExecutionSupport

/// Explicit developer launch mode; renders real AppKit/SwiftUI windows and exits.
@MainActor
enum SmokeTest {
    static func run(model: AppModel, directory: URL, reopen: Bool) async {
        if ProcessInfo.processInfo.arguments.contains("--localization-preview") {
            await localizationPreview(model: model, directory: directory)
            return
        }
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
            if ProcessInfo.processInfo.arguments.contains("--execution-only") {
                var setup = OnboardingState()
                setup.draft = LocalProfile(nickname: "C++ smoke", avatar: .leaf)
                check(model.saveOnboarding(setup, finish: true), "Execution setup persists")
                model.open(first)
                let code = "#include <iostream>\nint main(){int a,b;std::cin>>a>>b;std::cout<<a+b;}\n"
                model.execution.inputs[first.id] = "-7 -8\n"
                model.updateState(first.id) { $0.draft = code }
                model.update { $0.exercises["future.execution-empty"] = ExerciseProgress(); $0.exercises["future.execution-empty"]?.draft = "" }
                let before = try Data(contentsOf: model.dataURL)
                func waitForExecution() async throws {
                    let deadline = ContinuousClock.now.advanced(by: .seconds(45))
                    while model.execution.isBusy && ContinuousClock.now < deadline {
                        try await Task.sleep(for: .milliseconds(25))
                    }
                    if model.execution.isBusy { throw ContentError.invalid("Execution helper did not finish") }
                }
                check(model.execution.readiness == .unchecked, "Readiness starts unchecked")
                check(model.execution.checkReadiness(), "Readiness starts using the execution slot")
                check(!model.execution.run(exerciseID: first.id, source: code, stdin: ""), "Readiness owns the single execution slot")
                try await waitForExecution()
                check(model.execution.readiness == .ready, "Readiness compiles and runs a real isolated program")
                check(try Data(contentsOf: model.dataURL) == before, "Readiness leaves progress and drafts unchanged")
                check(model.execution.checkReadiness(), "Readiness can be retried")
                model.execution.cancel()
                try await waitForExecution()
                check(model.execution.readiness == .cancelled, "Cancelled readiness does not report success")
                check(try Data(contentsOf: model.dataURL) == before, "Cancelled readiness leaves progress unchanged")
                check(model.execution.checkReadiness(), "Cancelled readiness can be retried")
                try await waitForExecution()
                check(model.execution.readiness == .ready, "Retry after cancellation reaches a real ready environment")
                check(model.execution.checkReadiness(), "Readiness can start again for navigation cancel")
                model.page = .catalog
                try await waitForExecution()
                check(model.execution.readiness == .cancelled, "Leaving the lesson page cancels the running check")
                // Every panel state renders in a real window; forced states use explicit values.
                for (state, busy, stopping, name) in [(CodeExecutionController.Readiness.unchecked, false, false, "unchecked"),
                                      (.checking, true, false, "checking"), (.checking, true, true, "stopping"),
                                      (.ready, false, false, "ready"), (.failed, false, false, "failed"), (.cancelled, false, false, "cancelled")] {
                    let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
                                         styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                    panel.isReleasedWhenClosed = false
                    panel.contentView = NSHostingView(rootView: ExecutionReadinessPanel(
                        readiness: state, isBusy: busy, isStopping: stopping, onCheck: {}, onStop: {})
                        .padding(24).frame(maxWidth: 560).background(WorkspaceBackdrop())
                        .environment(\.locale, PresentationLocale.locale).preferredColorScheme(.light))
                    panel.orderFront(nil)
                    await settle()
                    try snapshot(window: panel, to: directory.appendingPathComponent("readiness-panel-\(name).png"))
                    check(panel.contentView != nil, "Readiness panel \(name) renders in a real window")
                    panel.close()
                }
                model.runCode(stdin: "-7 -8\n")
                check(model.execution.isBusy, "Run uses the real app execution controller")
                check(!model.execution.run(exerciseID: first.id, source: code, stdin: "0 0"), "Second VM request is refused while the slot is occupied")
                try await waitForExecution()
                check(model.execution.failure == nil, "Signed bundle and guest hashes pass inside the real app")
                check(model.execution.result?.status == .success && model.execution.result?.stdout == "-15", "Real packaged app compiles and runs stdin C++")
                check(try Data(contentsOf: model.dataURL) == before, "Running does not change persisted progress, awards or drafts")
                check(model.state(for: first.id).completion == .unfinished, "Successful execution is not automatic task completion")
                let console = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 980), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                console.contentView = NSHostingView(rootView: ExerciseEditorPreview(model: model, exercise: first).padding(24)
                    .frame(width: 880, height: 980, alignment: .topLeading).background(WorkspaceBackdrop())
                    .environment(\.locale, PresentationLocale.locale).preferredColorScheme(.light).tint(.green))
                console.orderFront(nil)
                await settle()
                check(findEditor(in: console.contentView) != nil, "Result preview renders the real unified code editor")
                try snapshot(window: console, to: directory.appendingPathComponent("execution-editor-success.png"))
                console.contentView = NSHostingView(rootView: ExerciseEditorPreview(model: model, exercise: first).padding(24)
                    .frame(width: 580, height: 980, alignment: .topLeading).background(WorkspaceBackdrop())
                    .environment(\.locale, PresentationLocale.locale).preferredColorScheme(.dark).tint(.green))
                await settle()
                try snapshot(window: console, to: directory.appendingPathComponent("execution-editor-compact-dark.png"))
                guard let gradeTask = course.exercises.first(where: {
                    ($0.gradingFixtures?.count ?? 0) >= 2 && $0.testCases.allSatisfy { !$0.output.isEmpty }
                }) else { throw ContentError.invalid("No multi-fixture task for grading smoke") }
                func gradingSummary() -> String {
                    let results = model.execution.gradingResults
                        .map { "\($0.index):\($0.status.rawValue)" }.joined(separator: ",")
                    return " [failure=\(model.execution.failure.map(String.init(describing:)) ?? "none"); results=\(results)]"
                }
                func checkGrading(_ condition: Bool, _ name: String) {
                    check(condition, condition ? name : name + gradingSummary())
                }
                model.open(gradeTask)
                model.updateState(gradeTask.id) { $0.draft = gradeTask.solution }
                let beforeGrade = try Data(contentsOf: model.dataURL)
                model.gradeCode()
                check(model.execution.isGrading && model.execution.isBusy, "Grading uses the real execution slot")
                check(!model.execution.run(exerciseID: gradeTask.id, source: gradeTask.solution, stdin: ""), "Run is refused while grading occupies the slot")
                check(!model.execution.checkReadiness(), "Readiness check is refused while grading occupies the slot")
                try await waitForExecution()
                checkGrading(model.execution.gradingResults.count == gradeTask.testCases.count, "Every verified fixture is executed")
                checkGrading(model.execution.gradingPassed, "Reference solution passes all fixtures")
                check(model.state(for: gradeTask.id).completion == .automatic
                      && model.state(for: gradeTask.id).lastCorrect == true
                      && model.state(for: gradeTask.id).attempts == 1, "Complete grading pass persists automatic completion")
                check(try Data(contentsOf: model.dataURL) != beforeGrade, "Grading result is persisted")
                console.contentView = NSHostingView(rootView: ExerciseEditorPreview(model: model, exercise: gradeTask).padding(24)
                    .frame(width: 880, height: 1100, alignment: .topLeading).background(WorkspaceBackdrop())
                    .environment(\.locale, PresentationLocale.locale).preferredColorScheme(.light).tint(.green))
                await settle()
                try snapshot(window: console, to: directory.appendingPathComponent("grading-editor-success.png"))
                model.updateState(gradeTask.id) { $0.draft = "int main(){}" }
                await settle()
                if let editor = findEditor(in: console.contentView) {
                    check(editor.string == "int main(){}", "Programmatic draft change reaches the real editor")
                } else { failures.append("Programmatic draft change has a real editor") }
                model.gradeCode()
                try await waitForExecution()
                checkGrading(model.execution.gradingResults.count == gradeTask.testCases.count
                      && model.execution.gradingResults.allSatisfy({ !$0.matches }), "Wrong program fails every fixture")
                check(model.state(for: gradeTask.id).attempts == 2
                      && model.state(for: gradeTask.id).lastCorrect == false
                      && model.state(for: gradeTask.id).completion == .automatic, "Failure records an attempt without revoking earned completion")
                await settle()
                try snapshot(window: console, to: directory.appendingPathComponent("grading-editor-failure.png"))
                // Readiness must not rewrite the editor's finished grading state.
                check(model.execution.checkReadiness(), "Readiness can start after a finished grading")
                check(model.execution.state == .finished && model.execution.isGrading
                      && model.execution.gradingResults.count == gradeTask.testCases.count,
                      "Readiness keeps the editor's finished grading state and results")
                check(!model.execution.isProgramBusy && model.execution.isBusy,
                      "Readiness occupies the slot without a program job")
                model.execution.cancel()
                try await waitForExecution()
                check(model.execution.readiness == .cancelled, "Cancelled readiness after grading reports cancellation")
                check(model.execution.state == .finished && model.execution.isGrading,
                      "Editor's grading state survives readiness cancellation")
                guard let fileTask = course.exercises.first(where: {
                    ($0.gradingFixtures?.count ?? 0) >= 5
                        && $0.testCases.contains { ($0.expectedFiles ?? [:]).isEmpty == false }
                }) else { throw ContentError.invalid("No file-fixture task for grading smoke") }
                model.open(fileTask)
                model.updateState(fileTask.id) { $0.draft = fileTask.solution }
                model.gradeCode()
                try await waitForExecution()
                checkGrading(model.execution.gradingResults.count == fileTask.testCases.count
                      && model.execution.gradingPassed, "File fixtures travel into the VM and verify inside it")
                check(model.state(for: fileTask.id).completion == .automatic, "File grading persists automatic completion")
                model.updateState(fileTask.id) { $0.draft = "int main(){}" }
                model.gradeCode()
                try await waitForExecution()
                checkGrading(!model.execution.gradingPassed
                      && model.execution.gradingResults.contains {
                          $0.status == .fileMismatch && !$0.mismatchedFiles.isEmpty
                      }, "Wrong program fails file fixtures with named mismatches")
                console.orderOut(nil)
                model.open(first)
                if let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) {
                    await settle()
                    try snapshot(window: window, to: directory.appendingPathComponent("execution-light.png"))
                    model.update { $0.preferences.theme = "dark" }
                    window.setContentSize(NSSize(width: 760, height: 740))
                    await settle()
                    try snapshot(window: window, to: directory.appendingPathComponent("execution-compact-dark.png"))
                }
                model.updateState(first.id) { $0.draft = "int main(){\n return missing;\n}" }
                model.runCode(stdin: "")
                try await waitForExecution()
                check(model.execution.result?.status == .compileError, "Real compiler error is not a successful execution")
                let diagnostics = CompilerDiagnostic.parse(model.execution.result?.stderr ?? "")
                check(diagnostics.first?.line == 2 && diagnostics.first?.column == 9, "Compiler diagnostics retain row and byte column")
                if let diagnostic = diagnostics.first {
                    let errorSource = model.state(for: first.id).draft ?? ""
                    let navigation = EditorNavigation(source: errorSource, line: diagnostic.line, byteColumn: diagnostic.column)
                    let editorWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 320), styleMask: [.titled], backing: .buffered, defer: false)
                    editorWindow.contentView = NSHostingView(rootView: CodeEditor(text: .constant(errorSource), fontSize: 16, navigation: navigation).frame(width: 600, height: 320))
                    editorWindow.orderFront(nil)
                    await settle()
                    if let editor = findEditor(in: editorWindow.contentView) {
                        check(editor.selectedRange().location == (errorSource as NSString).range(of: "missing").location, "Real NSTextView navigates to compiler diagnostic")
                        check(editor.string == errorSource && editor.undoManager?.canUndo != true, "Diagnostic navigation does not change source or create undo edits")
                    } else { failures.append("Diagnostic navigation has a real editor") }
                    editorWindow.orderOut(nil)
                }
                model.updateState(first.id) { $0.draft = "#include <unistd.h>\nint main(){sleep(90);}" }
                model.runCode(stdin: "")
                let bootDeadline = ContinuousClock.now.advanced(by: .seconds(10))
                while model.execution.isBusy && model.execution.state != .phase(.running) && ContinuousClock.now < bootDeadline {
                    try await Task.sleep(for: .milliseconds(25))
                }
                check(model.execution.state == .phase(.running), "UI receives the real running phase")
                model.execution.cancel()
                try await waitForExecution()
                check(model.execution.result?.status == .cancelled, "Stop reaps the real helper and VM")
                model.runCode(stdin: "")
                check(model.execution.isBusy, "Slot is reusable after cancellation")
                if let next = course.exercises.dropFirst().first { model.open(next) }
                try await waitForExecution()
                check(model.execution.result?.status == .cancelled, "Changing exercise cancels the old job")
                let document = try ProgressStore(url: model.dataURL).document
                check(document.exercises["future.execution-empty"]?.draft == "", "Execution leaves unknown empty drafts intact on disk")
                check(document.exercises[first.id]?.completion == .unfinished, "Run/compile error/cancel never grade the exercise")
                model.open(first)
                model.runCode(stdin: "")
                let windowList = NSApp.windows.compactMap {
                    ($0.isVisible && $0.contentView != nil) ? "\($0.className)/\($0.identifier?.rawValue ?? "-")" : nil
                }.joined(separator: "; ")
                if let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) { window.close() }
                try await waitForExecution()
                if model.execution.result?.status != .cancelled { failures.append("visible windows: \(windowList)") }
                check(model.execution.result?.status == .cancelled, "Closing the hosting window cancels the real job")
            } else if ProcessInfo.processInfo.arguments.contains("--settings-only") {
                var setup = OnboardingState()
                setup.draft = LocalProfile(nickname: "Ученик 👩🏽‍💻", avatar: .leaf)
                check(model.saveOnboarding(setup, finish: true), "Settings review creates an isolated persisted profile")
                guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else {
                    throw ContentError.invalid("Main window not found")
                }
                model.page = .progress
                await settle()
                try snapshot(window: window, to: directory.appendingPathComponent("progress-empty.png"))
                model.open(first)
                let draft = first.starter + "// настройки 👩🏽‍💻\n"
                model.updateState(first.id) { $0.draft = draft; $0.hintLevel = 2 }
                model.selfComplete()
                if let automatic = course.exercises.first(where: { $0.kind != .code && $0.answer != nil }) {
                    model.open(automatic)
                    model.updateState(automatic.id) { $0.answer = automatic.answer! }
                    model.check()
                    check(model.state(for: automatic.id).completion == .automatic, "Progress distinguishes a genuine automatic answer from self-review")
                }
                model.update {
                    var unknown = ExerciseProgress()
                    unknown.draft = ""
                    $0.exercises["future.settings-review"] = unknown
                    $0.preferences.textSize = 28
                    $0.preferences.codeSize = 26
                    $0.preferences.syntaxHighlighting = false
                    $0.preferences.showLineNumbers = false
                }
                guard let originalProfile = model.document.profile else { throw ContentError.invalid("Profile was not saved") }
                var edited = originalProfile
                edited.nickname = "Новый профиль 👩🏽‍💻"
                edited.avatar = .mountain
                let beforeEditing = try Data(contentsOf: model.dataURL)
                let profileWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 590), styleMask: [.titled], backing: .buffered, defer: false)
                profileWindow.contentView = NSHostingView(rootView: EditProfileView(model: model, profile: edited)
                    .environment(\.locale, PresentationLocale.locale).preferredColorScheme(.light))
                profileWindow.orderFront(nil)
                await settle()
                try snapshot(window: profileWindow, to: directory.appendingPathComponent("profile-edit.png"))
                check(try Data(contentsOf: model.dataURL) == beforeEditing, "Opening an edited profile does not commit its draft")
                profileWindow.orderOut(nil)
                check(model.saveProfile(edited), "Profile changes persist through the real save path")
                check(model.document.profile?.id == originalProfile.id && model.document.profile?.createdAt == originalProfile.createdAt, "Editing keeps profile identity and creation date")
                for theme in ["light", "dark"] {
                    model.update { $0.preferences.theme = theme }
                    model.page = .progress
                    window.setContentSize(NSSize(width: theme == "light" ? 1180 : 760, height: 780))
                    await settle()
                    try snapshot(window: window, to: directory.appendingPathComponent("progress-\(theme).png"))
                    let statistics = NSWindow(contentRect: NSRect(x: 0, y: 0, width: theme == "light" ? 920 : 600, height: 780), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                    statistics.contentView = NSHostingView(rootView: ProgressViewScreen(model: model)
                        .environment(\.locale, PresentationLocale.locale).preferredColorScheme(theme == "dark" ? .dark : .light)
                        .background(WorkspaceBackdrop()))
                    statistics.orderFront(nil)
                    await settle()
                    try snapshot(window: statistics, to: directory.appendingPathComponent("progress-detail-\(theme).png"))
                    statistics.orderOut(nil)
                    for pane in SettingsView.Pane.allCases {
                        let settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 780), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                        settings.contentView = NSHostingView(rootView: SettingsView(model: model, pane: pane)
                            .environment(\.locale, PresentationLocale.locale).preferredColorScheme(theme == "dark" ? .dark : .light))
                        settings.orderFront(nil)
                        await settle()
                        try snapshot(window: settings, to: directory.appendingPathComponent("settings-\(pane)-\(theme).png"))
                        if pane == .appearance {
                            settings.setContentSize(NSSize(width: 600, height: 560))
                            await settle()
                            try snapshot(window: settings, to: directory.appendingPathComponent("settings-compact-\(theme).png"))
                        }
                        check(settings.contentView != nil, "Settings pane renders: \(pane), \(theme), maximum font sizes")
                        settings.orderOut(nil)
                    }
                }
                model.update { $0.preferences.textSize = Preferences().textSize }
                check(model.document.preferences.codeSize == 26, "Resetting course text size keeps the code size")
                let restored = try ProgressStore(url: model.dataURL).document
                check(restored.profile?.nickname == edited.nickname && restored.profile?.avatar == .mountain, "New profile survives reopening the real progress file")
                check(restored.exercises[first.id]?.draft == draft && restored.exercises[first.id]?.completion == .selfReviewed, "Settings changes preserve code and self-review")
                check(restored.exercises["future.settings-review"]?.draft == "", "Settings changes retain unknown IDs and deliberately empty drafts")
                check(restored.preferences.codeSize == 26 && !restored.preferences.syntaxHighlighting && !restored.preferences.showLineNumbers, "Editor preferences survive reopening")
                check(!model.hasUnsavedChanges && model.saveError == nil, "Profile and preferences finish with no pending writes")
            } else if reopen {
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
                let accessibleWelcome = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 340), styleMask: [.titled], backing: .buffered, defer: false)
                accessibleWelcome.contentView = NSHostingView(rootView: WelcomeCodePanel(reduceMotion: true, reduceTransparency: true))
                accessibleWelcome.orderFront(nil)
                await settle()
                try snapshot(window: accessibleWelcome, to: directory.appendingPathComponent("welcome-reduced-motion-transparency.png"))
                check(accessibleWelcome.contentView != nil, "Static opaque welcome renders with reduced motion and transparency")
                accessibleWelcome.orderOut(nil)
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
                model.page = .home
                model.update { $0.preferences.theme = "dark" }
                await settle()
                try snapshot(window: window, to: directory.appendingPathComponent("home-dark.png"))
                window.setContentSize(NSSize(width: 760, height: 700))
                await settle()
                try snapshot(window: window, to: directory.appendingPathComponent("home-compact-dark.png"))
                check(window.contentLayoutRect.width >= 750, "Redesigned home keeps compact native navigation")
                window.setContentSize(NSSize(width: 1180, height: 800))
                model.update { $0.preferences.theme = "light" }
                model.open(first)
                await settle()
                let theoryWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 740), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                theoryWindow.contentView = NSHostingView(rootView: LessonView(model: model, showTheory: true)
                    .environment(\.locale, PresentationLocale.locale).preferredColorScheme(model.colorScheme).background(WorkspaceBackdrop()))
                theoryWindow.orderFront(nil)
                await settle()
                check(findEditor(in: theoryWindow.contentView)?.string == first.starter, "Theory side panel leaves the real editor and draft intact")
                try snapshot(window: theoryWindow, to: directory.appendingPathComponent("lesson-theory-wide.png"))
                theoryWindow.setContentSize(NSSize(width: 760, height: 660))
                await settle()
                if let sheet = theoryWindow.attachedSheet {
                    check(true, "Compact lesson opens theory in a native sheet")
                    try snapshot(window: sheet, to: directory.appendingPathComponent("lesson-theory-sheet.png"))
                    theoryWindow.endSheet(sheet)
                    sheet.orderOut(nil)
                } else { failures.append("Compact lesson opens theory in a native sheet") }
                theoryWindow.orderOut(nil)
                window.makeKeyAndOrderFront(nil)
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
                settings.contentView = NSHostingView(rootView: SettingsView(model: model).environment(\.locale, PresentationLocale.locale).preferredColorScheme(.dark))
                settings.orderFront(nil)
                await settle()
                try snapshot(window: settings, to: directory.appendingPathComponent("settings-dark.png"))
                settings.orderOut(nil)
                let diagnostic = AppFailure(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError,
                    userInfo: [NSLocalizedDescriptionKey: "No space left on device · %@ 🚀"]), operation: .export)
                check(String(localized: diagnostic.resource()).contains("На диске недостаточно места"), "System failure summary follows explicit app locale")
                check(diagnostic.diagnostics?.contains("No space left on device · %@ 🚀") == true, "Original system diagnostic remains literal and separate")
                let diagnosticWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 570, height: 240), styleMask: [.titled], backing: .buffered, defer: false)
                diagnosticWindow.contentView = NSHostingView(rootView: FailureText(failure: diagnostic, fallback: "Не удалось загрузить ресурс")
                    .environment(\.locale, PresentationLocale.locale)
                    .frame(width: 522, alignment: .leading).padding(24)
                    .frame(width: 570, height: 240, alignment: .topLeading)
                    .background(Color(nsColor: .windowBackgroundColor)))
                diagnosticWindow.orderFront(nil)
                await settle()
                try snapshot(window: diagnosticWindow, to: directory.appendingPathComponent("system-error-summary.png"))
                check(diagnosticWindow.contentView != nil, "Localized error and diagnostics disclosure render in native window")
                check(diagnosticWindow.contentView?.bounds.height == 240, "Diagnostic smoke window keeps its compact viewport")
                diagnosticWindow.orderOut(nil)
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

    /// Developer-only, isolated draft preview; not a language switch or acceptance test.
    private static func localizationPreview(model: AppModel, directory: URL) async {
        var checks: [String] = []
        var failures: [String] = []
        var menuBeforePreview: [String] = []
        var menuDuringPreview: [String] = []
        var menuAfterPreview: [String] = []
        var englishMenuItemsPresent = false
        var missingEnglishMenuTitles: [String] = []
        var staleRussianMenuTitles: [String] = []
        func check(_ condition: Bool, _ name: String) {
            if condition { checks.append(name) } else { failures.append(name) }
        }
        func settle() async { try? await Task.sleep(for: .milliseconds(250)) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let path = ProcessInfo.processInfo.environment["CODEPATH_LOCALIZATION_SOURCE"] else {
                throw ContentError.invalid("Developer localization source is missing")
            }
            guard let isolatedData = ProcessInfo.processInfo.environment["CODEPATH_DATA_DIR"] else {
                throw ContentError.invalid("Developer preview requires an isolated data directory")
            }
            let russian = try Course.bundled()
            let russianCatalog = try CourseCatalog.bundled(availableCourseIDs: [russian.id])
            let exercise = russian.exercises[0]
            guard let originalChoice = russian.exercises.first(where: { $0.kind == .choice }),
                  let originalAnswer = originalChoice.answer else {
                throw ContentError.invalid("Russian preview fixture has no canonical choice")
            }
            var setup = OnboardingState()
            setup.draft = LocalProfile(nickname: "Пилот 👩🏽‍💻", avatar: .leaf)
            check(model.saveOnboarding(setup, finish: true), "Isolated profile is saved")
            model.updateState(exercise.id) { $0.draft = ""; $0.answer = "literal %@"; $0.hintLevel = 1 }
            let awardDate = Date(timeIntervalSince1970: 1_700_000_000)
            model.update {
                var choiceState = ExerciseProgress()
                choiceState.answer = originalAnswer
                choiceState.completion = .automatic
                choiceState.attempts = 2
                $0.exercises[originalChoice.id] = choiceState
                var future = ExerciseProgress()
                future.draft = "// будущий черновик 👩🏽‍💻"
                $0.exercises["future.preview.exercise"] = future
                $0.lessonPositions = ["future.preview.lesson": "future.preview.exercise"]
                if $0.achievements == nil { $0.achievements = AchievementState() }
                $0.achievements?.awards["future.preview.award"] = AchievementAward(recognizedAt: awardDate, historical: true)
            }
            let before = try Data(contentsOf: model.dataURL)
            await settle()
            menuBeforePreview = menuTitles(in: NSApp.mainMenu)
            let russianMenu = ["О codelib", "История обновлений", "Продолжить обучение", "Обучение",
                               "Предыдущее задание", "Следующее задание", "Сохранить изменения"]
            check(russianMenu.allSatisfy(menuBeforePreview.contains), "App menu initially uses Russian")
            try model.previewEnglishForSmoke(sourceRoot: URL(fileURLWithPath: path, isDirectory: true))
            await settle()
            menuDuringPreview = menuTitles(in: NSApp.mainMenu)
            let appItems = NSApp.mainMenu?.items.first?.submenu?.items.map(\.title) ?? []
            let learningItems = NSApp.mainMenu?.items.first(where: { $0.title == "Learning" })?
                .submenu?.items.map(\.title) ?? []
            missingEnglishMenuTitles = ["About codelib", "Release history"].filter { !appItems.contains($0) }
            missingEnglishMenuTitles += ["Previous task", "Next task", "Save changes"].filter { !learningItems.contains($0) }
            if !menuDuringPreview.contains("Continue learning") { missingEnglishMenuTitles.append("Continue learning") }
            if !menuDuringPreview.contains("Learning") { missingEnglishMenuTitles.append("Learning") }
            staleRussianMenuTitles = ["О codelib", "История обновлений"].filter(appItems.contains)
            staleRussianMenuTitles += ["Предыдущее задание", "Следующее задание", "Сохранить изменения"]
                .filter(learningItems.contains)
            if menuDuringPreview.contains("Продолжить обучение") { staleRussianMenuTitles.append("Продолжить обучение") }
            englishMenuItemsPresent = missingEnglishMenuTitles.isEmpty && staleRussianMenuTitles.isEmpty
            if ProcessInfo.processInfo.arguments.contains("--strict-menu-localization") {
                check(englishMenuItemsPresent, "Expected English app menu titles are in place without stale Russian titles")
            }
            check(model.presentationLocale.language.languageCode?.identifier == "en", "Preview uses explicit English locale")
            check(model.course?.lessons.first?.title == "Programs and main", "Preview projects English course")
            check(model.catalog?.entries.first?.title != russianCatalog.entries.first?.title,
                  "Preview projects English catalog")
            check(model.releaseHistory?.releases.first?.title == "Checking the C++ environment", "Preview projects English history")
            let theory = LocalizedStringResource("Теория", locale: model.presentationLocale)
            check(String(localized: theory) == "Theory", "Compiled app catalog resolves English UI")
            guard let englishCourse = model.course,
                  let choice = englishCourse.exercises.first(where: { $0.kind == .choice }),
                  let canonicalAnswer = choice.answer else {
                throw ContentError.invalid("English preview has no canonical choice")
            }
            check(choice.choiceLabel(for: canonicalAnswer) != canonicalAnswer, "Choice label is translated")
            check(AnswerChecker.check(canonicalAnswer, for: choice) == true, "Canonical answer still checks correctly")
            check(AnswerChecker.check(choice.choiceLabel(for: canonicalAnswer), for: choice) == false,
                  "Translated label is not substituted for the canonical answer")
            let failure = AppFailure(StorageError.locked, operation: .importProgress)
            check(String(localized: failure.resource(locale: model.presentationLocale)) ==
                  "Import canceled; current data has been preserved: Another process is writing progress. Try saving again.",
                  "Nested error and context use the same English locale")
            let reasons: [(StorageError, String, String)] = [
                (.unsupportedVersion(7), "Версия данных 7 не поддерживается. Файл не изменён.",
                 "Data version 7 is not supported. The file has not been changed."),
                (.invalidData, "Файл прогресса повреждён или содержит недопустимые значения. Файл не изменён.",
                 "The progress file is damaged or contains invalid values. The file has not been changed."),
                (.conflictingRevision, "Данные изменены другим экземпляром приложения. Закройте и откройте codelib снова.",
                 "Another instance of the app has changed the data. Close and reopen codelib."),
                (.locked, "Другой процесс записывает прогресс. Повторите сохранение.",
                 "Another process is writing progress. Try saving again."),
                (.protectedExport, "Выберите другой файл экспорта: нельзя заменять рабочий прогресс, резервную копию или служебные файлы.",
                 "Choose a different export file: you cannot replace active progress, its backup or internal files.")
            ]
            let operations: [(AppFailure.Operation, String, String)] = [
                (.export, "Не удалось экспортировать: ", "Export failed: "),
                (.importProgress, "Импорт отменён, текущие данные сохранены: ", "Import canceled; current data has been preserved: "),
                (.reset, "Сброс не выполнен: ", "Reset failed: "),
                (.restore, "Восстановление не выполнено: ", "Restore failed: ")
            ]
            for (reason, ruDetail, enDetail) in reasons {
                for (operation, ruPrefix, enPrefix) in operations {
                    let contextual = AppFailure(reason, operation: operation)
                    check(String(localized: contextual.resource(locale: Locale(identifier: "ru"))) == ruPrefix + ruDetail,
                          "Russian storage failure: \(reason), \(operation)")
                    check(String(localized: contextual.resource(locale: Locale(identifier: "en"))) == enPrefix + enDetail,
                          "English storage failure: \(reason), \(operation)")
                }
            }
            let diagnosticLiteral = "opaque %@ · Пилот 👩🏽‍💻"
            let opaqueFailure = AppFailure(ContentError.invalid(diagnosticLiteral), operation: .export)
            check(String(localized: opaqueFailure.resource(locale: Locale(identifier: "en"))) == "Export failed: \(diagnosticLiteral)",
                  "Opaque legacy diagnostic stays literal inside English context")
            let systemFailure = AppFailure(NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES),
                                                    userInfo: [NSLocalizedDescriptionKey: "misleading %@"]),
                                           operation: .importProgress)
            check(String(localized: systemFailure.resource(locale: Locale(identifier: "en"))) ==
                  "Import canceled; current data has been preserved: Access to the file was denied. Check permissions or choose another location." &&
                  systemFailure.diagnostics?.contains("misleading %@") == true,
                  "System error uses English domain-code summary while retaining opaque diagnostics")
            check(model.state(for: exercise.id).draft == "" && model.state(for: exercise.id).answer == "literal %@",
                  "Empty draft and literal answer survive preview")
            check(!model.selectContentLanguage(.russian), "Preview cannot commit a language selection")
            check(try Data(contentsOf: model.dataURL) == before, "Preview does not write progress")

            // Exercise the same validated import/export methods used by native
            // panels, but only in a new isolated data directory.
            let fixtureRoot = URL(fileURLWithPath: isolatedData, isDirectory: true)
            let exportURL = fixtureRoot.appendingPathComponent("preview-export.json")
            try model.exportProgress(to: exportURL)
            let importedRoot = fixtureRoot.appendingPathComponent("imported-progress", isDirectory: true)
            setenv("CODEPATH_DATA_DIR", importedRoot.path, 1)
            let imported = AppModel()
            setenv("CODEPATH_DATA_DIR", isolatedData, 1)
            try imported.previewEnglishForSmoke(sourceRoot: URL(fileURLWithPath: path, isDirectory: true))
            imported.importProgress(from: exportURL)
            check(imported.message == nil && imported.storageError == nil && !imported.hasUnsavedChanges,
                  "English preview imports exported progress")
            check(imported.document.profile == model.document.profile && imported.document.profile?.id != nil,
                  "Export and import preserve profile identity")
            check(imported.state(for: exercise.id).draft == "" && imported.state(for: exercise.id).answer == "literal %@" &&
                  imported.state(for: exercise.id).hintLevel == 1,
                  "Export and import preserve empty draft, literal answer and hint")
            check(imported.state(for: originalChoice.id).answer == originalAnswer &&
                  imported.state(for: originalChoice.id).completion == .automatic &&
                  AnswerChecker.check(imported.state(for: originalChoice.id).answer, for: choice) == true,
                  "Imported canonical choice remains correctly checked in English")
            check(imported.document.lessonPositions?["future.preview.lesson"] == "future.preview.exercise" &&
                  imported.state(for: "future.preview.exercise").draft == "// будущий черновик 👩🏽‍💻" &&
                  imported.document.achievements?.awards["future.preview.award"]?.recognizedAt == awardDate &&
                  imported.document.achievements?.awards["future.preview.award"]?.historical == true,
                  "Export and import preserve unknown positions, draft and award")
            check(imported.document.preferences.preferredLanguage == model.document.preferences.preferredLanguage,
                  "Export and import do not invent a language preference")
            let importedBytes = try Data(contentsOf: imported.dataURL)
            let invalidURL = fixtureRoot.appendingPathComponent("invalid-preview-import.json")
            try Data("{invalid".utf8).write(to: invalidURL)
            imported.importProgress(from: invalidURL)
            let afterInvalidImport = try Data(contentsOf: imported.dataURL)
            check(imported.message != nil && afterInvalidImport == importedBytes,
                  "Invalid English-preview import leaves imported progress untouched")
            setenv("CODEPATH_DATA_DIR", importedRoot.path, 1)
            let reopenedImport = AppModel()
            setenv("CODEPATH_DATA_DIR", isolatedData, 1)
            check(reopenedImport.document.profile == model.document.profile &&
                  reopenedImport.state(for: exercise.id).draft == "" &&
                  reopenedImport.state(for: originalChoice.id).answer == originalAnswer &&
                  reopenedImport.document.achievements?.awards["future.preview.award"]?.recognizedAt == awardDate,
                  "Imported progress survives reopening")
            check(try Data(contentsOf: model.dataURL) == before, "Export and separate import leave original progress untouched")

            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
                                  styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.contentView = NSHostingView(rootView: HomeView(model: model).environment(\.locale, model.presentationLocale))
            window.orderFront(nil)
            await settle()
            try snapshot(window: window, to: directory.appendingPathComponent("english-home.png"))
            window.contentView = NSHostingView(rootView: LessonView(model: model).environment(\.locale, model.presentationLocale))
            await settle()
            check(findEditor(in: window.contentView)?.string == "", "English lesson renders the deliberately empty draft")
            try snapshot(window: window, to: directory.appendingPathComponent("english-lesson.png"))
            window.contentView = NSHostingView(rootView: SettingsView(model: model).environment(\.locale, model.presentationLocale))
            await settle()
            try snapshot(window: window, to: directory.appendingPathComponent("english-settings.png"))
            window.contentView = NSHostingView(rootView: ReleaseHistoryView(model: model).environment(\.locale, model.presentationLocale))
            await settle()
            try snapshot(window: window, to: directory.appendingPathComponent("english-history.png"))
            window.contentView = NSHostingView(rootView: AchievementCollectionView(model: model).environment(\.locale, model.presentationLocale))
            await settle()
            try snapshot(window: window, to: directory.appendingPathComponent("english-achievements.png"))
            window.contentView = NSHostingView(rootView: CatalogView(model: model).environment(\.locale, model.presentationLocale))
            await settle()
            try snapshot(window: window, to: directory.appendingPathComponent("english-catalog.png"))
            window.contentView = NSHostingView(rootView: SyllabusView(model: model).environment(\.locale, model.presentationLocale))
            await settle()
            try snapshot(window: window, to: directory.appendingPathComponent("english-syllabus.png"))
            window.contentView = NSHostingView(rootView: ProgressViewScreen(model: model).environment(\.locale, model.presentationLocale))
            await settle()
            try snapshot(window: window, to: directory.appendingPathComponent("english-progress.png"))
            window.contentView = NSHostingView(rootView: OnboardingView(model: model).environment(\.locale, model.presentationLocale))
            await settle()
            try snapshot(window: window, to: directory.appendingPathComponent("english-onboarding-welcome.png"))
            window.contentView = NSHostingView(rootView: FailureText(failure: failure, fallback: "Не удалось загрузить ресурс",
                                                                     locale: model.presentationLocale)
                .padding(24).environment(\.locale, model.presentationLocale))
            await settle()
            try snapshot(window: window, to: directory.appendingPathComponent("english-error.png"))
            window.contentView = NSHostingView(rootView: RootView(model: model).environment(\.locale, model.presentationLocale))
            await settle()
            try snapshot(window: window, to: directory.appendingPathComponent("english-root.png"))
            for pane in [SettingsView.Pane.appearance, .data] {
                window.contentView = NSHostingView(rootView: SettingsView(model: model, pane: pane)
                    .environment(\.locale, model.presentationLocale))
                await settle()
                try snapshot(window: window, to: directory.appendingPathComponent("english-settings-\(pane.rawValue).png"))
            }
            for step in [OnboardingState.Step.profile, .appearance, .environment] {
                let fixture = URL(fileURLWithPath: isolatedData, isDirectory: true)
                    .appendingPathComponent("onboarding-\(step.rawValue)", isDirectory: true)
                setenv("CODEPATH_DATA_DIR", fixture.path, 1)
                let onboardingModel = AppModel()
                setenv("CODEPATH_DATA_DIR", isolatedData, 1)
                var state = OnboardingState()
                state.draft = LocalProfile(nickname: "Preview", avatar: .leaf)
                state.step = step
                check(onboardingModel.saveOnboarding(state), "Isolated onboarding fixture saves: \(step.rawValue)")
                let onboardingBytes = try Data(contentsOf: onboardingModel.dataURL)
                try onboardingModel.previewEnglishForSmoke(sourceRoot: URL(fileURLWithPath: path, isDirectory: true))
                window.contentView = NSHostingView(rootView: OnboardingView(model: onboardingModel)
                    .environment(\.locale, onboardingModel.presentationLocale))
                await settle()
                try snapshot(window: window, to: directory.appendingPathComponent("english-onboarding-\(step.rawValue).png"))
                check(try Data(contentsOf: onboardingModel.dataURL) == onboardingBytes,
                      "Onboarding preview does not write fixture: \(step.rawValue)")
            }
            model.endEnglishSmokePreview()
            await settle()
            menuAfterPreview = menuTitles(in: NSApp.mainMenu)
            check(russianMenu.allSatisfy(menuAfterPreview.contains), "App menu is Russian after preview")
            window.orderOut(nil)
            check(model.presentationLocale == PresentationLocale.locale && model.course?.lessons.first?.title == russian.lessons.first?.title,
                  "Closing preview restores Russian content")
            check(try Data(contentsOf: model.dataURL) == before, "RU/EN preview round trip leaves progress unchanged")
        } catch { failures.append(String(describing: error)) }
        do {
            let report: [String: Any] = ["checks": checks, "failures": failures, "developerOnly": true,
                                         "menuBeforePreview": menuBeforePreview, "menuDuringPreview": menuDuringPreview,
                                         "menuAfterPreview": menuAfterPreview, "englishMenuItemsPresent": englishMenuItemsPresent,
                                         "missingEnglishMenuTitles": missingEnglishMenuTitles,
                                         "staleRussianMenuTitles": staleRussianMenuTitles]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("localization-preview-report.json"), options: .atomic)
        } catch { failures.append(String(describing: error)) }
        print("Localization preview: \(checks.count) checks; failures: \(failures)")
        exit(failures.isEmpty ? 0 : 1)
    }

    /// Compact preview for the execution screenshots. Evaluating the observable
    /// progress inside a real body keeps programmatic draft changes flowing into
    /// the hosted AppKit editor exactly as the lesson screen does in the app.
    private struct ExerciseEditorPreview: View {
        let model: AppModel
        let exercise: Exercise
        var body: some View {
            let _ = model.state(for: exercise.id)
            ExerciseView(model: model, exercise: exercise, revealEditor: {}).responseArea
        }
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

    private static func menuTitles(in menu: NSMenu?) -> [String] {
        guard let menu else { return [] }
        return menu.items.flatMap { [$0.title] + menuTitles(in: $0.submenu) }
    }

    private static func snapshot(window: NSWindow, to url: URL) throws {
        window.displayIfNeeded()
        // cacheDisplay omits composited native sidebars/glass. Capture the actual window
        // when already permitted; never request or change system permissions in smoke.
        if CGPreflightScreenCaptureAccess() {
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l\(window.windowNumber)", url.path]
            try capture.run()
            capture.waitUntilExit()
            if capture.terminationStatus == 0 { return }
        }
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
