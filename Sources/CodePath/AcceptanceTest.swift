#if DEBUG
import AppKit
import ApplicationServices
import Darwin
import LearningCore
import SwiftUI

/// Shared failure policy: these checks are also exercised without GUI or TCC.
enum AcceptanceValidation {
    static func missingCaptures(required: Set<String>, recorded: Set<String>, existingFiles: Set<String>) -> [String] {
        required.subtracting(recorded.intersection(existingFiles)).sorted()
    }

    static func axFailure(nodeCount: Int, truncated: Bool) -> String? {
        if nodeCount == 0 { return "не получен" }
        if truncated { return "усечён" }
        return nil
    }

    static func measurementFailure(hasBitmap: Bool, maxOffset: Double, first: Double, last: Double,
                                   physicalBefore: UInt64?, physicalAfter: UInt64?,
                                   cpuBefore: Double?, cpuAfter: Double?) -> String? {
        guard hasBitmap else { return "перерисовка не подтверждена" }
        guard maxOffset > 0, last > first, abs(last - maxOffset) <= 2 else { return "не достигнут конец документа" }
        guard physicalBefore != nil, physicalAfter != nil, let cpuBefore, let cpuAfter,
              cpuAfter >= cpuBefore else { return "CPU или physical footprint не измерены" }
        return nil
    }

    static func exitCode(failures: [String]) -> Int32 { failures.isEmpty ? 0 : 1 }
}

/// Developer-only acceptance run (part 2): renders real windows, captures every
/// screen in the agreed sizes/themes, inventories accessibility elements, samples
/// memory/CPU and synchronous scroll redraw. It never changes system settings and
/// never claims visual/VoiceOver acceptance: the produced artifacts are material
/// for the human pass described in ACCEPTANCE_PART2.md.
@MainActor
enum AcceptanceTest {
    static func run(model: AppModel, directory: URL) async {
        let recorder = Recorder(directory: directory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try await recorder.execute(model: model)
        } catch {
            recorder.failures.append("Прогон прерван: \(error)")
        }
        do {
            try recorder.writeReport(model: model)
        } catch {
            recorder.failures.append("Не удалось записать отчёт: \(error)")
        }
        print("Acceptance: \(recorder.captures.count) captures; failures: \(recorder.failures)")
        exit(AcceptanceValidation.exitCode(failures: recorder.failures))
    }
}

@MainActor
private final class Recorder {
    struct AXNode {
        let screen: String
        let parentIndex: Int?
        let role: String
        let label: String
        let title: String
        let value: String
        let placeholder: String
        let frame: CGRect
        let chrome: Bool

        var json: [String: Any] {
            ["role": role, "label": label, "title": title, "value": value,
             "parentIndex": parentIndex as Any? ?? NSNull(), "chrome": chrome,
             "placeholder": placeholder,
             "frame": ["x": frame.origin.x, "y": frame.origin.y,
                       "width": frame.width, "height": frame.height]]
        }
    }

    struct CaptureRecord {
        let name: String
        let screen: String
        let theme: String
        let textSize: Double
        let width: CGFloat
        let height: CGFloat
        let file: String
        let systemCapture: Bool
        let axTotal: Int
        let axInteractive: Int
        let axUnlabeled: Int
        let axUnknown: Int
    }

    static let interactiveRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXComboBox",
        "AXMenuButton", "AXTextField", "AXSearchField", "AXSlider", "AXTab",
        "AXLink", "AXDisclosureTriangle", "AXColorWell", "AXDateField", "AXTimeField"
    ]

    /// Window chrome and scroll machinery: real UI, but not authored content.
    static let chromeRoles: Set<String> = [
        "AXScrollBar", "AXValueIndicator", "AXSplitter", "AXWindow",
        "AXScrollArea", "AXMenuBar", "AXMenuBarItem", "AXMenu"
    ]

    /// Standard window buttons (traffic lights) are chrome, not authored labels.
    static let chromeSubroles: Set<String> = [
        "AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton"
    ]

    /// Roles whose children are mechanical parts (arrows, knobs), not content.
    static let chromePropagatingRoles: Set<String> = [
        "AXScrollBar", "AXValueIndicator", "AXSplitter"
    ]

    let directory: URL
    var captures: [CaptureRecord] = []
    var inventories: [String: [AXNode]] = [:]
    var truncatedInventories = Set<String>()
    var axDiagnostics: [String: Any] = [:]
    var unlabeled: [AXNode] = []
    var zeroSized: [AXNode] = []
    var duplicates: [String] = []
    var failures: [String] = []
    var findings: [String] = []
    var uniqueFindings: [String] {
        var seen = Set<String>()
        return findings.filter { seen.insert($0).inserted }
    }
    var metrics: [String: Any] = [:]
    var fullscreenCaptured = false
    var fullscreenRequested = false
    let screenCaptureAllowed = CGPreflightScreenCaptureAccess()

    init(directory: URL) {
        self.directory = directory
    }

    func check(_ condition: Bool, _ name: String) {
        if !condition { failures.append(name) }
    }

    func settle(_ milliseconds: Int = 260) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    // MARK: - Run

    func execute(model: AppModel) async throws {
        check(model.contentError == nil, "Курс загружается в приложении")
        check(model.storageError == nil, "Файл прогресса открывается")
        guard let course = model.course else { throw ContentError.invalid("Курс не загружен") }
        check(course.exercises.count == 348 && course.lessons.count == 71,
              "Курс: 17 разделов, 71 урок, 348 заданий")
        let first = course.exercises[0]
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else {
            throw ContentError.invalid("Главное окно не найдено")
        }

        metrics["os"] = ProcessInfo.processInfo.operatingSystemVersionString
        metrics["screen"] = NSScreen.main.map { "\(Int($0.frame.width))x\(Int($0.frame.height))" } ?? "-"
        metrics["screenCapturePermission"] = screenCaptureAllowed
        metrics["captures"] = 0

        // An inactive app exposes no SwiftUI accessibility tree, and this helper
        // runs from a shell, not from a foreground launch. Activating the app is
        // an app-level action, not a change to system settings.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        await settle(500)
        metrics["appActiveAtStart"] = NSApp.isActive
        metrics["keyWindowAtStart"] = window.isKeyWindow

        // The first AX query on a fresh process may race the accessibility
        // bridge; establish and warm it once before recording anything.
        _ = collectAX(screen: "warmup", window: window)
        try? await Task.sleep(for: .milliseconds(600))

        // Onboarding is the first run state of a fresh isolated data directory.
        await size(window, 1180, 800)
        await capture("onboarding-welcome-system", screen: "onboarding", window: window,
                      theme: "system", textSize: Preferences().textSize)

        for (name, step, theme) in [("welcome-light", nil, "light"), ("welcome-dark", nil, "dark"),
                                    ("profile-light", OnboardingState.Step.profile, "light"),
                                    ("appearance-light", .appearance, "light"),
                                    ("environment-light", .environment, "light")] {
            try await onboardingStep(name: name, step: step, theme: theme)
        }

        var setup = OnboardingState()
        setup.draft = LocalProfile(nickname: "Пилот приёмки", avatar: .leaf)
        check(model.saveOnboarding(setup, finish: true), "Изолированный профиль сохраняется")

        // Main pages: wide light/dark and compact light, real navigation window.
        for (page, name) in [(AppModel.Page.home, "home"), (.catalog, "catalog"),
                             (.syllabus, "syllabus"), (.progress, "progress"),
                             (.achievements, "achievements")] {
            for (theme, sizeName, width, height) in [("light", "wide", CGFloat(1180), CGFloat(800)),
                                                     ("dark", "wide", 1180, 800),
                                                     ("light", "compact", 760, 700)] {
                model.update { $0.preferences.theme = theme }
                model.page = page
                applyAppearance(theme, to: window)
                await size(window, width, height)
                await capture("\(name)-\(sizeName)-\(theme)", screen: name, window: window,
                              theme: theme, textSize: model.document.preferences.textSize)
            }
        }

        // Observed in the capture itself: the sidebar gives the profile name a
        // single truncated line even at the ideal width. Recorded for the manual
        // pass rather than silently "fixed" during acceptance work.
        findings.append("Сайдбар: имя профиля «Пилот приёмки» обрезается до «Пилот пр…»; проверить длинные имена.")

        // Achievement banner auto-dismisses after five seconds; capture it promptly.
        model.update { $0.preferences.achievementSounds = false }
        if let award = AchievementCatalog.all.first {
            for (theme, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
                model.achievementNotifications = [award.id]
                let banner = makeWindow(NSRect(x: 0, y: 0, width: 900, height: 130), style: [.titled])
                applyAppearance(theme, to: banner)
                banner.contentView = NSHostingView(rootView: AchievementBanner(model: model, forceOpaque: true)
                    .environment(\.locale, PresentationLocale.locale)
                    .preferredColorScheme(scheme)
                    .environment(\.colorScheme, scheme)
                    // Glass never rasterizes through cacheDisplay, so the banner
                    // is captured in its Reduce Transparency fallback; the glass
                    // rendering itself remains a manual visual check.
                    .frame(width: 900, height: 130)
                    .background(WorkspaceBackdrop()))
                banner.orderFront(nil)
                await settle(350)
                await capture("achievement-banner-reduced-\(theme)", screen: "achievement-banner-reduced", window: banner,
                              theme: theme, textSize: model.document.preferences.textSize)
                findings.append("Баннер достижения снят в режиме Reduce Transparency; стеклянный вариант требует ручного прохода.")
                banner.orderOut(nil)
                banner.close()
                model.achievementNotifications.removeAll()
            }
        }

        // Lesson screen: practice and the inline first step at both widths.
        model.update { $0.preferences.theme = "light" }
        model.open(first)
        for (theme, sizeName, width, height) in [("light", "wide", CGFloat(1180), CGFloat(800)),
                                                 ("dark", "wide", 1180, 800),
                                                 ("light", "compact", 760, 700),
                                                 ("dark", "compact", 760, 700)] {
            model.update { $0.preferences.theme = theme }
            applyAppearance(theme, to: window)
            await size(window, width, height)
            await capture("lesson-\(sizeName)-\(theme)", screen: "lesson", window: window,
                          theme: theme, textSize: model.document.preferences.textSize)
        }
        model.update { $0.preferences.theme = "light"; $0.preferences.textSize = 28; $0.preferences.codeSize = 26 }
        applyAppearance("light", to: window)
        await size(window, 1180, 800)
        await capture("lesson-wide-light-maxtext", screen: "lesson", window: window,
                      theme: "light", textSize: 28)
        model.update { $0.preferences.textSize = Preferences().textSize; $0.preferences.codeSize = Preferences().codeSize }

        model.openLesson(course.lessons[0])
        for (name, width, height) in [("wide", CGFloat(1180), CGFloat(800)), ("compact", 760, 660)] {
            await size(window, width, height)
            await capture("lesson-theory-\(name)-light", screen: "lesson-theory", window: window,
                          theme: "light", textSize: model.document.preferences.textSize)
            check(window.attachedSheet == nil && model.exercise == nil, "Теория открыта в основном окне: \(name)")
        }

        // Secondary screens that own their own window.
        let savedTheme = model.document.preferences.theme
        for (theme, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            model.update { $0.preferences.theme = theme }
            for (section, size, suffix) in [
                (SettingsView.Section.profile, SettingsView.defaultSize, "profile"),
                (.appearance, SettingsView.defaultSize, "appearance"),
                (.appearance, SettingsView.minimumSize, "appearance-compact"),
                (.data, SettingsView.defaultSize, "data")
            ] {
                let settings = makeWindow(NSRect(origin: .zero, size: size), style: [.titled, .resizable])
                applyAppearance(theme, to: settings)
                settings.contentView = NSHostingView(rootView: SettingsView(model: model, initialSection: section == .profile ? nil : section)
                    .environment(\.locale, PresentationLocale.locale)
                    .preferredColorScheme(scheme)
                    .environment(\.colorScheme, scheme))
                settings.orderFront(nil)
                await settle()
                await capture("settings-\(suffix)-\(theme)", screen: "settings-\(section)",
                              window: settings, theme: theme, textSize: model.document.preferences.textSize)
                settings.orderOut(nil)
                settings.close()
            }

            let history = makeWindow(NSRect(x: 0, y: 0, width: 680, height: 720), style: [.titled, .resizable])
            applyAppearance(theme, to: history)
            history.contentView = NSHostingView(rootView: ReleaseHistoryView(model: model)
                .environment(\.locale, PresentationLocale.locale)
                .preferredColorScheme(scheme)
                .environment(\.colorScheme, scheme))
            history.orderFront(nil)
            await settle()
            await capture("history-\(theme)", screen: "history", window: history, theme: theme,
                          textSize: model.document.preferences.textSize)
            history.orderOut(nil)
            history.close()

            let about = makeWindow(NSRect(x: 0, y: 0, width: 620, height: 620), style: [.titled, .resizable])
            applyAppearance(theme, to: about)
            about.contentView = NSHostingView(rootView: AboutView(model: model)
                .environment(\.locale, PresentationLocale.locale)
                .preferredColorScheme(scheme)
                .environment(\.colorScheme, scheme))
            about.orderFront(nil)
            await settle()
            await capture("about-\(theme)", screen: "about", window: about, theme: theme,
                          textSize: model.document.preferences.textSize)
            about.orderOut(nil)
            about.close()
        }
        model.update { $0.preferences.theme = savedTheme }

        if let profile = model.document.profile {
            var edited = profile
            edited.nickname = "Профиль приёмки"
            let profileWindow = makeWindow(NSRect(x: 0, y: 0, width: 600, height: 620), style: [.titled, .resizable])
            applyAppearance("light", to: profileWindow)
            profileWindow.contentView = NSHostingView(rootView: EditProfileView(model: model, profile: edited)
                .environment(\.locale, PresentationLocale.locale)
                .preferredColorScheme(.light)
                .environment(\.colorScheme, .light))
            profileWindow.orderFront(nil)
            await settle()
            await capture("profile-edit-light", screen: "profile-edit", window: profileWindow,
                          theme: "light", textSize: model.document.preferences.textSize)
            profileWindow.orderOut(nil)
            profileWindow.close()
        }

        let failure = AppFailure(StorageError.locked, operation: .export)
        let failureWindow = makeWindow(NSRect(x: 0, y: 0, width: 640, height: 300), style: [.titled, .resizable])
        applyAppearance("light", to: failureWindow)
        failureWindow.contentView = NSHostingView(rootView: FailureText(failure: failure,
                                                                       fallback: "Не удалось загрузить ресурс")
            .environment(\.locale, PresentationLocale.locale)
            .preferredColorScheme(.light)
            .environment(\.colorScheme, .light)
            .padding(24)
            .frame(width: 640, height: 300, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor)))
        failureWindow.orderFront(nil)
        await settle()
        await capture("error-light", screen: "error", window: failureWindow, theme: "light",
                      textSize: model.document.preferences.textSize)
        failureWindow.orderOut(nil)
        failureWindow.close()

        let welcome = makeWindow(NSRect(x: 0, y: 0, width: 560, height: 340), style: [.titled])
        applyAppearance("light", to: welcome)
        welcome.contentView = NSHostingView(rootView: WelcomeCodePanel(reduceMotion: true, reduceTransparency: true)
            .environment(\.locale, PresentationLocale.locale)
            .preferredColorScheme(.light)
            .environment(\.colorScheme, .light))
        welcome.orderFront(nil)
        await settle()
        await capture("welcome-reduced-motion-transparency-light", screen: "welcome-reduced",
                      window: welcome, theme: "light", textSize: model.document.preferences.textSize)
        welcome.orderOut(nil)
        welcome.close()

        // One real fullscreen sample; per-screen fullscreen remains a manual check.
        model.update { $0.preferences.theme = "light" }
        model.page = .home
        applyAppearance("light", to: window)
        await size(window, 1180, 800)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        await settle(400)
        metrics["appActiveBeforeFullscreen"] = NSApp.isActive
        metrics["keyWindowBeforeFullscreen"] = window.isKeyWindow
        fullscreenRequested = true
        var enterAttempts = 0
        while enterAttempts < 3 && !fullscreenCaptured {
            enterAttempts += 1
            if enterAttempts > 1 { await settle(1500) }
            window.toggleFullScreen(nil)
            fullscreenCaptured = await waitForFullscreen(window, enter: true, timeout: 4)
        }
        metrics["fullscreenEnterAttempts"] = enterAttempts
        if fullscreenCaptured {
            // The style mask flips at the start of the animation; a second toggle
            // issued mid-flight is silently ignored by AppKit.
            try? await Task.sleep(for: .milliseconds(1200))
            await capture("home-fullscreen-light", screen: "home-fullscreen", window: window,
                          theme: "light", textSize: model.document.preferences.textSize)
        }
        let exitStart = ContinuousClock.now
        var exited = await exitFullscreen(window, timeout: 6)
        if !exited {
            await settle(1200)
            exited = await exitFullscreen(window, timeout: 6)
        }
        if !exited {
            findings.append("Полноэкранный режим не закрылся: окно осталось в .fullScreen после двух попыток.")
            failures.append("Не удалось выйти из полноэкранного режима")
        }
        metrics["fullscreenRequested"] = fullscreenRequested
        metrics["fullscreenCaptured"] = fullscreenCaptured
        metrics["fullscreenExited"] = exited
        let exitElapsed = ContinuousClock.now - exitStart
        metrics["fullscreenExitSeconds"] = Double(exitElapsed.components.seconds)
            + Double(exitElapsed.components.attoseconds) / 1e18

        // Keyboard focus chain as currently configured; Full Keyboard Access is a
        // system setting and is not changed by this run.
        model.open(first)
        await size(window, 1180, 800)
        await settle(350)
        metrics["keyViewChain"] = keyViewChain(window: window)
        metrics["initialFirstResponder"] = window.initialFirstResponder.map { String(describing: type(of: $0)) } ?? "nil"

        metrics["performance"] = await performance(model: model, window: window, exercise: first)
        metrics["captures"] = captures.count
        var required = Set(["onboarding-welcome-system", "onboarding-welcome-light", "onboarding-welcome-dark",
                            "onboarding-profile-light", "onboarding-appearance-light", "onboarding-environment-light",
                            "achievement-banner-reduced-light", "achievement-banner-reduced-dark",
                            "lesson-wide-light", "lesson-wide-dark", "lesson-compact-light", "lesson-compact-dark",
                            "lesson-wide-light-maxtext", "lesson-theory-wide-light", "lesson-theory-compact-light",
                            "profile-edit-light", "error-light", "welcome-reduced-motion-transparency-light",
                            "home-fullscreen-light", "lesson-scroll-end-light"])
        for page in ["home", "catalog", "syllabus", "progress", "achievements"] {
            for suffix in ["wide-light", "wide-dark", "compact-light"] { required.insert("\(page)-\(suffix)") }
        }
        for theme in ["light", "dark"] {
            for pane in ["appearance", "appearance-compact", "profile", "data"] {
                required.insert("settings-\(pane)-\(theme)")
            }
            required.insert("history-\(theme)")
            required.insert("about-\(theme)")
        }
        let existingFiles = Set(captures.filter {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.file).path)
        }.map(\.name))
        let missing = AcceptanceValidation.missingCaptures(required: required,
                                                           recorded: Set(captures.map(\.name)),
                                                           existingFiles: existingFiles)
        if !missing.isEmpty { failures.append("Отсутствуют обязательные снимки: \(missing.sorted().joined(separator: ", "))") }

        for screen in inventories.keys where inventories[screen]?.isEmpty == true {
            findings.append("Экран «\(screen)» не отдал ни одного accessibility-элемента.")
        }
        if !screenCaptureAllowed {
            findings.append("Нет разрешения screencapture: снимки сделаны через cacheDisplay; чистое стекло (панель приветствия, баннер в обычном режиме) в них не растрируется и проверяется вручную.")
        }
        if !unlabeled.isEmpty {
            findings.append("Интерактивные элементы без подписи: \(unlabeled.count). См. report.json → accessibility.unlabeled.")
        }
        if !zeroSized.isEmpty {
            findings.append("Интерактивные элементы с нулевым размером: \(zeroSized.count).")
        }
        if !duplicates.isEmpty {
            findings.append("Повторяющиеся подписи элементов: \(duplicates.count) групп.")
        }
    }

    /// Programmatic windows default to `isReleasedWhenClosed`; ARC would then
    /// release them a second time when the local variable goes away.
    private func makeWindow(_ rect: NSRect, style: NSWindow.StyleMask = [.titled, .resizable]) -> NSWindow {
        let window = NSWindow(contentRect: rect, styleMask: style, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    private func waitForFullscreen(_ window: NSWindow, enter: Bool, timeout: Double) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while ContinuousClock.now < deadline {
            if window.styleMask.contains(.fullScreen) == enter { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return window.styleMask.contains(.fullScreen) == enter
    }

    private func exitFullscreen(_ window: NSWindow, timeout: Double) async -> Bool {
        guard window.styleMask.contains(.fullScreen) else { return true }
        window.toggleFullScreen(nil)
        return await waitForFullscreen(window, enter: false, timeout: timeout)
    }

    // MARK: - Onboarding fixtures

    private func onboardingStep(name: String, step: OnboardingState.Step?, theme: String) async throws {
        let dataRoot = ProcessInfo.processInfo.environment["CODEPATH_DATA_DIR"] ?? directory.path
        let fixture = URL(fileURLWithPath: dataRoot, isDirectory: true)
            .appendingPathComponent("onboarding-fixture-\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        let previous = ProcessInfo.processInfo.environment["CODEPATH_DATA_DIR"]
        _ = setenv("CODEPATH_DATA_DIR", fixture.path, 1)
        let model = AppModel()
        if let step {
            var state = OnboardingState()
            state.step = step
            state.draft = LocalProfile(nickname: "Пилот приёмки", avatar: .leaf)
            check(model.saveOnboarding(state), "Шаг onboarding сохраняется: \(step)")
        }
        if let previous { _ = setenv("CODEPATH_DATA_DIR", previous, 1) } else { _ = unsetenv("CODEPATH_DATA_DIR") }
        // OnboardingStep's own `.preferredColorScheme` follows model preferences,
        // so the fixture model must agree with the theme being captured.
        model.update { $0.preferences.theme = theme }
        let window = makeWindow(NSRect(x: 0, y: 0, width: 900, height: 760), style: [.titled, .resizable])
        applyAppearance(theme, to: window)
        let host = NSHostingView(rootView: OnboardingView(model: model)
            .environment(\.locale, PresentationLocale.locale)
            .preferredColorScheme(theme == "dark" ? .dark : .light)
            .environment(\.colorScheme, theme == "dark" ? .dark : .light))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: window.contentLayoutRect.size)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.orderFront(nil)
        await settle(400)
        await capture("onboarding-\(name)", screen: "onboarding", window: window, theme: theme,
                      textSize: model.document.preferences.textSize)
        window.orderOut(nil)
        window.close()
    }

    // MARK: - Capture and accessibility

    private func size(_ window: NSWindow, _ width: CGFloat, _ height: CGFloat) async {
        window.setContentSize(NSSize(width: width, height: height))
        await settle(320)
    }

    /// A bare NSHostingView does not inherit the scene's `preferredColorScheme`;
    /// without this, dark system appearance would render light-theme windows
    /// with white-on-white text. Capture-time only, never changes app behavior.
    private func applyAppearance(_ theme: String, to window: NSWindow) {
        window.appearance = NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)
    }

    private func capture(_ name: String, screen: String, window: NSWindow,
                         theme: String, textSize: Double) async {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        await settle(150)
        window.displayIfNeeded()
        let file = "\(name).png"
        var systemCapture = false
        do {
            let shot = try snapshot(window: window, theme: theme, to: directory.appendingPathComponent(file))
            systemCapture = shot.system
            if shot.blank {
                findings.append("Снимок \(name) не записан: поверхность полностью стеклянная и без разрешения записи экрана даёт однотонное изображение. Нужен ручной проход.")
                failures.append("Обязательный снимок \(name) пуст")
                return
            }
        } catch {
            failures.append("Снимок \(name): \(error)")
            return
        }
        var nodes: [AXNode] = []
        // The AX bridge and window server update asynchronously, especially
        // while opening a new NSHostingView. Retry the actual target window,
        // never replace a missing tree with another capture's inventory.
        for attempt in 0..<5 {
            if attempt > 0 {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                await settle(400)
            }
            nodes = collectAX(screen: name, window: window)
            if !nodes.isEmpty { break }
        }
        inventories[name] = nodes
        if let reason = AcceptanceValidation.axFailure(nodeCount: nodes.count, truncated: truncatedInventories.contains(name)) {
            failures.append("AX-инвентарь \(name): \(reason)")
            metrics["axFailure-\(name)"] = axDiagnostics
        }
        if !nodes.isEmpty { computeDuplicates(screen: name, nodes: nodes) }
        let interactive = nodes.filter { Self.interactiveRoles.contains($0.role) && !$0.chrome }
        let withoutLabel = interactive.filter {
            $0.frame.width >= 2 && $0.frame.height >= 2
                && $0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.placeholder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        unlabeled.append(contentsOf: withoutLabel)
        zeroSized.append(contentsOf: interactive.filter { $0.frame.width < 1 || $0.frame.height < 1 })
        captures.append(CaptureRecord(name: name, screen: screen, theme: theme, textSize: textSize,
                                      width: window.contentLayoutRect.width,
                                      height: window.contentLayoutRect.height, file: file,
                                      systemCapture: systemCapture, axTotal: nodes.count,
                                      axInteractive: interactive.count,
                                      axUnlabeled: withoutLabel.count,
                                      axUnknown: nodes.filter { $0.role == "AXUnknown" || $0.role.isEmpty }.count))
    }

    /// The in-process NSAccessibility tree hides SwiftUI content until an AX
    /// client connects. Querying our own application through the AX API does
    /// connect that client without Apple Events or screen-recording consent, so
    /// the inventory matches what VoiceOver is offered (roles, labels, order).
    private func collectAX(screen: String, window: NSWindow) -> [AXNode] {
        guard let root = axWindow(for: window) else { return [] }
        var nodes: [AXNode] = []
        func visit(_ element: AXUIElement, depth: Int, chrome: Bool, parent: Int?) {
            guard depth < 60, nodes.count < 3000 else {
                truncatedInventories.insert(screen)
                return
            }
            let role = axString(element, kAXRoleAttribute)
            let label = axString(element, kAXDescriptionAttribute)
            let title = axString(element, kAXTitleAttribute)
            let subrole = axString(element, kAXSubroleAttribute)
            let placeholder = axString(element, kAXPlaceholderValueAttribute)
            var value = ""
            if let raw = axAttribute(element, kAXValueAttribute) {
                if let text = raw as? String { value = text }
                else if let number = raw as? NSNumber { value = number.stringValue }
            }
            let isChrome = chrome || Self.chromeRoles.contains(role)
                || Self.chromeSubroles.contains(subrole)
            // Chrome roles describe window furniture, not their content: a scroll
            // area must not taint every control inside it as "chrome".
            let propagatesChrome = chrome || Self.chromePropagatingRoles.contains(role)
            let index = nodes.count
            nodes.append(AXNode(screen: screen, parentIndex: parent, role: role, label: label, title: title,
                                value: value, placeholder: placeholder,
                                frame: axFrame(element), chrome: isChrome))
            for child in axChildren(element) {
                visit(child, depth: depth + 1, chrome: propagatesChrome, parent: index)
            }
        }
        visit(root, depth: 0, chrome: false, parent: nil)
        return nodes
    }

    private func axWindow(for window: NSWindow) -> AXUIElement? {
        let application = AXUIElementCreateApplication(getpid())
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let target = CGRect(x: window.frame.origin.x,
                            y: screenHeight - window.frame.maxY,
                            width: window.frame.width,
                            height: window.frame.height)
        axDiagnostics = ["target": "\(target)", "appActive": NSApp.isActive,
                         "windowKey": window.isKeyWindow, "windowVisible": window.isVisible]
        if let raw = axAttribute(application, kAXWindowsAttribute),
           let windows = raw as? [AXUIElement] {
            axDiagnostics["windows"] = windows.map { "\(axFrame($0))" }
            let matches = windows.filter { candidate in
                let frame = axFrame(candidate)
                return abs(frame.minX - target.minX) < 3 && abs(frame.minY - target.minY) < 3
                    && abs(frame.width - target.width) < 3 && abs(frame.height - target.height) < 3
            }
            if matches.count == 1 { return matches[0] }
            axDiagnostics["matches"] = matches.count
            // Identical geometry does not identify which window owns the tree.
            if matches.count > 1 { return nil }
        }
        // Fallback for sheet/child windows that the window list reports oddly.
        let point = CGPoint(x: window.frame.midX, y: screenHeight - window.frame.midY)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(application, Float(point.x), Float(point.y), &hit) == .success,
              var current = hit else { return nil }
        for _ in 0..<40 {
            if axString(current, kAXRoleAttribute) == "AXWindow" {
                let frame = axFrame(current)
                guard abs(frame.minX - target.minX) < 3, abs(frame.minY - target.minY) < 3,
                      abs(frame.width - target.width) < 3, abs(frame.height - target.height) < 3 else {
                    return nil
                }
                return current
            }
            guard let parent = axAttribute(current, kAXParentAttribute),
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            current = unsafeDowncast(parent, to: AXUIElement.self)
        }
        return nil
    }

    private func axAttribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func axString(_ element: AXUIElement, _ name: String) -> String {
        axAttribute(element, name) as? String ?? ""
    }

    private func axChildren(_ element: AXUIElement) -> [AXUIElement] {
        guard let raw = axAttribute(element, kAXChildrenAttribute) else { return [] }
        return raw as? [AXUIElement] ?? []
    }

    private func axFrame(_ element: AXUIElement) -> CGRect {
        var point = CGPoint.zero
        var size = CGSize.zero
        if let position = axAttribute(element, kAXPositionAttribute),
           CFGetTypeID(position) == AXValueGetTypeID() {
            AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &point)
        }
        if let extent = axAttribute(element, kAXSizeAttribute),
           CFGetTypeID(extent) == AXValueGetTypeID() {
            AXValueGetValue(unsafeDowncast(extent, to: AXValue.self), .cgSize, &size)
        }
        return CGRect(origin: point, size: size)
    }

    private func computeDuplicates(screen: String, nodes: [AXNode]) {
        guard !duplicates.contains(where: { $0.hasPrefix(screen + ":") }) else { return }
        var counts: [String: Int] = [:]
        for node in nodes where Self.interactiveRoles.contains(node.role) && !node.chrome {
            let label = node.label.isEmpty ? node.title : node.label
            guard !label.isEmpty else { continue }
            counts["\(node.role)|\(label)", default: 0] += 1
        }
        for (key, count) in counts.sorted(by: { $0.key < $1.key }) where count > 1 {
            duplicates.append("\(screen): \(count)× \(key)")
        }
    }

    private func keyViewChain(window: NSWindow) -> [String] {
        var chain: [String] = []
        var visited = Set<ObjectIdentifier>()
        var current = window.initialFirstResponder
        while let view = current, chain.count < 200 {
            guard visited.insert(ObjectIdentifier(view)).inserted else {
                chain.append("↻ цикл на \(shortViewName(view))")
                break
            }
            chain.append(shortViewName(view))
            current = view.nextKeyView
        }
        return chain
    }

    private func shortViewName(_ view: NSView) -> String {
        let full = String(describing: type(of: view))
        if full.hasPrefix("AppKitWindowHostingView") { return "HostingView" }
        if full.hasPrefix("AppKitPlatformViewHost") { return "PlatformViewHost" }
        return full.split(separator: "<").first.map(String.init) ?? full
    }

    // MARK: - Performance

    private func performance(model: AppModel, window: NSWindow, exercise: Exercise) async -> [String: Any] {
        model.open(exercise)
        applyAppearance("light", to: window)
        await size(window, 1180, 800)
        model.updateState(exercise.id) {
            $0.draft = (1...1000).map { "// строка \($0) для проверки прокрутки" }.joined(separator: "\n")
        }
        await settle(500)
        guard let editor = findEditor(in: window.contentView),
              let scroll = editor.enclosingScrollView,
              let document = scroll.documentView else {
            failures.append("Замер прокрутки не выполнен: редактор не найден")
            return ["note": "Редактор или его прокрутка не найдены; замер не выполнен."]
        }
        let residentBefore = residentBytes()
        let cpuBefore = cpuSeconds()
        let maxOffset = max(0, document.bounds.height - scroll.contentView.bounds.height)
        let steps = 240
        var durations: [Double] = []
        // Force real drawing of the visible viewport: displayIfNeeded alone defers
        // layer work and would report a misleadingly small number.
        let bitmap = scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds)
        var firstOffset: CGFloat = 0
        var lastOffset: CGFloat = 0
        for index in 0..<steps {
            let target = maxOffset * CGFloat(index) / CGFloat(max(1, steps - 1))
            let start = DispatchTime.now().uptimeNanoseconds
            scroll.contentView.scroll(to: NSPoint(x: 0, y: target))
            scroll.reflectScrolledClipView(scroll.contentView)
            scroll.documentView?.layoutSubtreeIfNeeded()
            if let bitmap { scroll.cacheDisplay(in: scroll.bounds, to: bitmap) }
            else { window.displayIfNeeded() }
            let end = DispatchTime.now().uptimeNanoseconds
            if index == 0 { firstOffset = scroll.contentView.bounds.origin.y }
            lastOffset = scroll.contentView.bounds.origin.y
            durations.append(Double(end - start) / 1_000_000)
        }
        let residentAfter = residentBytes()
        let cpuAfter = cpuSeconds()
        if let reason = AcceptanceValidation.measurementFailure(
            hasBitmap: bitmap != nil, maxOffset: Double(maxOffset),
            first: Double(firstOffset), last: Double(lastOffset),
            physicalBefore: residentBefore, physicalAfter: residentAfter,
            cpuBefore: cpuBefore, cpuAfter: cpuAfter
        ) {
            failures.append("Замер прокрутки: \(reason)")
        }
        let sorted = durations.sorted()
        func percentile(_ fraction: Double) -> Double {
            guard !sorted.isEmpty else { return 0 }
            return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * fraction))]
        }
        await capture("lesson-scroll-end-light", screen: "lesson-scroll", window: window,
                      theme: "light", textSize: model.document.preferences.textSize)
        return ["note": "Синхронная перерисовка шагов прокрутки в тестовом процессе, не покадровый FPS.",
                "drawingMethod": bitmap == nil ? "displayIfNeeded" : "cacheDisplay",
                "steps": steps,
                "documentHeight": document.bounds.height,
                "residentBeforeMB": residentBefore.map { Double($0) / 1_048_576 } as Any? ?? NSNull(),
                "residentAfterScrollMB": residentAfter.map { Double($0) / 1_048_576 } as Any? ?? NSNull(),
                "cpuSecondsDuringScroll": cpuBefore.flatMap { before in cpuAfter.map { $0 - before } } as Any? ?? NSNull(),
                "scrollFirstOffset": firstOffset,
                "scrollLastOffset": lastOffset,
                "scrollMedianMS": percentile(0.5),
                "scrollP95MS": percentile(0.95),
                "scrollMaxMS": sorted.last ?? 0]
    }

    private func residentBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }

    private func cpuSeconds() -> Double? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        func seconds(_ value: timeval) -> Double {
            Double(value.tv_sec) + Double(value.tv_usec) / 1_000_000
        }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    private func findEditor(in view: NSView?) -> EditingTextView? {
        guard let view else { return nil }
        if let editor = view as? EditingTextView { return editor }
        for child in view.subviews {
            if let editor = findEditor(in: child) { return editor }
        }
        return nil
    }

    // MARK: - Files

    private func snapshot(window: NSWindow, theme: String, to url: URL) throws -> (system: Bool, blank: Bool) {
        window.displayIfNeeded()
        if screenCaptureAllowed {
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l\(window.windowNumber)", url.path]
            try capture.run()
            capture.waitUntilExit()
            if capture.terminationStatus == 0,
               let data = try? Data(contentsOf: url),
               let image = NSBitmapImageRep(data: data), !isBlank(image) {
                return (true, false)
            }
        }
        guard let view = window.contentView else { throw ContentError.invalid("Нет содержимого окна") }
        guard let cache = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw ContentError.invalid("Не удалось создать снимок")
        }
        view.cacheDisplay(in: view.bounds, to: cache)
        // cacheDisplay leaves material and window backing transparent, which a
        // PNG viewer shows as black and which would hide light-theme text.
        // Flatten the snapshot over the background of the captured theme.
        let bounds = NSRect(origin: .zero, size: view.bounds.size)
        let canvas = NSImage(size: bounds.size)
        canvas.lockFocus()
        background(theme: theme).setFill()
        bounds.fill()
        cache.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
        canvas.unlockFocus()
        guard let tiff = canvas.tiffRepresentation, let image = NSBitmapImageRep(data: tiff) else {
            throw ContentError.invalid("Не удалось создать снимок")
        }
        let blank = isBlank(image)
        guard !blank, let data = image.representation(using: .png, properties: [:]) else {
            if blank { return (false, true) }
            throw ContentError.invalid("Не удалось закодировать PNG")
        }
        try data.write(to: url)
        return (false, false)
    }

    /// A cacheDisplay fallback can come out uniformly black when a surface is
    /// pure glass; such a file would look like a defect instead of a tool limit.
    /// Role of the backing fill: a SwiftUI window may report a clear or white
    /// `backgroundColor`, which would hide light-theme text. Resolve the standard
    /// window color in the appearance the capture is meant to represent.
    private func background(theme: String) -> NSColor {
        let name: NSAppearance.Name
        switch theme {
        case "dark": name = .darkAqua
        case "light": name = .aqua
        default:
            let systemDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            name = systemDark ? .darkAqua : .aqua
        }
        guard let appearance = NSAppearance(named: name) else { return .windowBackgroundColor }
        // `windowBackgroundColor` is a dynamic color: it must be resolved while
        // the target appearance is current, otherwise the system appearance wins.
        var color = NSColor.windowBackgroundColor
        appearance.performAsCurrentDrawingAppearance {
            color = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) ?? .windowBackgroundColor
        }
        return color
    }

    private func isBlank(_ image: NSBitmapImageRep) -> Bool {
        var colors = Set<UInt32>()
        let stepX = max(1, image.pixelsWide / 32)
        let stepY = max(1, image.pixelsHigh / 32)
        for y in stride(from: 0, to: image.pixelsHigh, by: stepY) {
            for x in stride(from: 0, to: image.pixelsWide, by: stepX) {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    colors.insert(0xFF00FF)
                    continue
                }
                let red = UInt32(color.redComponent * 255)
                let green = UInt32(color.greenComponent * 255)
                let blue = UInt32(color.blueComponent * 255)
                colors.insert(red << 16 | green << 8 | blue)
                if colors.count > 1 { return false }
            }
        }
        return colors.count <= 1
    }

    func writeReport(model: AppModel) throws {
        let version = model.appRelease?.version.rawValue ?? "-"
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "-"
        let report: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "app": ["version": version, "build": build],
            "environment": metrics,
            "captures": captures.map { [
                "name": $0.name, "screen": $0.screen, "theme": $0.theme, "textSize": $0.textSize,
                "width": $0.width, "height": $0.height, "file": $0.file,
                "systemCapture": $0.systemCapture, "axTotal": $0.axTotal,
                "axInteractive": $0.axInteractive, "axUnlabeled": $0.axUnlabeled, "axUnknown": $0.axUnknown,
                "axStatus": truncatedInventories.contains($0.name) ? "truncated" : ($0.axTotal == 0 ? "unavailable" : "collected")
            ] },
            "accessibility": [
                "unlabeled": unlabeled.map { $0.json.merging(["screen": $0.screen]) { _, new in new } },
                "zeroSized": zeroSized.map { $0.json.merging(["screen": $0.screen]) { _, new in new } },
                "duplicates": duplicates
            ],
            "findings": uniqueFindings,
            "failures": failures,
            "limitations": [
                "VoiceOver: речь, ротор, порядок обхода и объявления проверяются только человеком.",
                "AX-инвентарь получен через API собственного процесса; полнота и порядок VoiceOver, речь, ротор и объявления не проверены.",
                "Full Keyboard Access — системная настройка; прогон её не меняет и снимает только текущую цепочку key view.",
                "Reduce Motion/Reduce Transparency — системные настройки; явные значения используются только там, где представление их принимает.",
                "Полноэкранный режим снят один раз как образец; покадровая приёмка каждого экрана остаётся ручной.",
                "Чистое стекло (панель приветствия, баннер достижения в обычном режиме) не растрируется через cacheDisplay: баннер снят в режиме Reduce Transparency, стеклянный вариант проверяется вручную.",
                "Сайдбар и обычные материалы сняты композитом поверх фона темы; за стеклянными поверхностями фон окна может отличаться от системного.",
                "Внешний вид оценивает человек: снимки — материал, а не вердикт."
            ],
            "developerOnly": true,
            "notAcceptance": true
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("report.json"), options: .atomic)
        let inventory: [String: Any] = inventories.mapValues { nodes in
            nodes.map { $0.json.merging(["screen": $0.screen]) { _, new in new } }
        }
        try JSONSerialization.data(withJSONObject: inventory, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("accessibility-inventory.json"), options: .atomic)
        try summaryMarkdown(version: version, build: build).data(using: .utf8)?
            .write(to: directory.appendingPathComponent("SUMMARY.md"), options: .atomic)
    }

    private func summaryMarkdown(version: String, build: String) -> String {
        var lines: [String] = []
        lines.append("# Приёмка часть 2 — автоматический прогон")
        lines.append("")
        lines.append("Версия \(version) / build \(build), \(ISO8601DateFormatter().string(from: Date())).")
        lines.append("")
        lines.append("Это материал для ручной приёмки, **не** подтверждение visual/VoiceOver-приёмки.")
        lines.append("")
        lines.append("## Снимки")
        lines.append("")
        lines.append("| Экран | Размер | Тема | Шрифт | A11y | Без подписи | Файл |")
        lines.append("|---|---|---|---|---|---|---|")
        for capture in captures {
            let ax = capture.axTotal == 0 ? "не получен" : (truncatedInventories.contains(capture.name) ? "усечён" : "\(capture.axTotal)")
            let unlabeledCount = capture.axTotal == 0 || truncatedInventories.contains(capture.name) ? "не проверено" : "\(capture.axUnlabeled)"
            lines.append("| \(capture.screen) | \(Int(capture.width))×\(Int(capture.height)) | \(capture.theme) | \(Int(capture.textSize)) | \(ax) | \(unlabeledCount) | `\(capture.file)` |")
        }
        lines.append("")
        lines.append("## Машинные наблюдения")
        lines.append("")
        if let fullscreen = metrics["fullscreenCaptured"] as? Bool {
            lines.append("- Полноэкранный режим: \(fullscreen ? "включился и снят" : "не включился в тестовом процессе").")
        }
        let complete = captures.filter { $0.axTotal > 0 && !truncatedInventories.contains($0.name) }.count
        lines.append("- Снимков: \(captures.count); AX-инвентарей получено без усечения: \(complete)/\(captures.count).")
        lines.append("- Эвристика на полученных деревьях: без подписи \(unlabeled.count); нулевого размера \(zeroSized.count); групп повторов \(duplicates.count). Это не подтверждение доступности.")
        lines.append("- AX-данные получены через API собственного процесса; полнота, речь, ротор и порядок VoiceOver требуют ручной проверки.")
        if let performance = metrics["performance"] as? [String: Any],
           let median = performance["scrollMedianMS"] as? Double,
           let p95 = performance["scrollP95MS"] as? Double,
           let maximum = performance["scrollMaxMS"] as? Double,
           let resident = performance["residentAfterScrollMB"] as? Double,
           let cpu = performance["cpuSecondsDuringScroll"] as? Double {
            lines.append(String(format: "- Прокрутка 1000 строк: медиана %.2f мс, p95 %.2f мс, максимум %.2f мс; CPU %.2f с; physical footprint %.0f МиБ.", median, p95, maximum, cpu, resident))
        } else {
            lines.append("- Замер прокрутки не выполнен.")
        }
        if let chain = metrics["keyViewChain"] as? [String], !chain.isEmpty {
            let stepWord = chain.count % 10 == 1 && chain.count % 100 != 11 ? "шаг"
                : ([2, 3, 4].contains(chain.count % 10) && ![12, 13, 14].contains(chain.count % 100) ? "шага" : "шагов")
            lines.append("- Цепочка key view: \(chain.count) \(stepWord) (\(chain.prefix(8).joined(separator: " → "))). Только AppKit-хостинг: элементы SwiftUI входят в Tab-порядок при Full Keyboard Access/VoiceOver — это ручная проверка.")
        } else {
            lines.append("- Цепочка key view пуста: Tab-порядок нужно проверять вручную, Full Keyboard Access — системная настройка.")
        }
        lines.append("")
        if !uniqueFindings.isEmpty {
            lines.append("## Находки до ручного прохода")
            lines.append("")
            for finding in uniqueFindings { lines.append("- \(finding)") }
            lines.append("")
        }
        if !failures.isEmpty {
            lines.append("## Сбои прогона")
            lines.append("")
            for failure in failures { lines.append("- \(failure)") }
            lines.append("")
        }
        lines.append("## Что проверяет человек (чек-лист)")
        lines.append("")
        lines.append("Для каждого экрана из таблицы, в светлой и тёмной теме, широком и компактном окне:")
        lines.append("")
        lines.append("- [ ] Нет обрезанного или наложенного текста, переносы читаются, крупный шрифт не ломает макет.")
        lines.append("- [ ] VoiceOver: заголовок экрана, назначение элементов, порядок обхода, доступные действия; нет «пустых» кнопок.")
        lines.append("- [ ] Full Keyboard Access: Tab/Shift-Tab достигают всех действий, фокус видим, Order не сбивается.")
        lines.append("- [ ] Fullscreen: макет не растягивается и не теряет боковую навигацию.")
        lines.append("- [ ] Reduce Motion: приветствие и баннеры не анимируются бесконечно.")
        lines.append("- [ ] Reduce Transparency: панели остаются читаемыми без стекла.")
        lines.append("")
        lines.append("Системные настройки этот прогон не меняет. Снимки — отправная точка, вердикт ставит человек.")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
#endif
