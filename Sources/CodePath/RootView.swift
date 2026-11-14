import SwiftUI
import LearningCore
import AppKit

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let error = model.contentError {
                VStack {
                    ContentUnavailableView("Не удалось загрузить курс", systemImage: "exclamationmark.triangle", description: Text(error.resource()))
                    FailureDiagnostics(failure: error)
                }.padding()
            } else if let error = model.storageError {
                VStack(spacing: 20) {
                    ContentUnavailableView("Прогресс не открыт", systemImage: "externaldrive.badge.exclamationmark",
                                           description: Text("\(String(localized: error.resource()))\nИсходный файл не изменён. Можно восстановить предыдущую сохранённую версию из резервной копии."))
                    Text(model.dataURL.path).font(.caption).textSelection(.enabled)
                    FailureDiagnostics(failure: error)
                    Button("Восстановить резервную копию") { model.restoreBackup() }
                    Text("Перед восстановлением исходный файл будет сохранён отдельно. Если резервной копии нет, операция ничего не изменит.")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: 520)
                }.padding()
            } else if model.startupRoute == .onboarding {
                OnboardingView(model: model)
            } else {
                workspace
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(ExecutionWindowObserver { model.execution.cancel() }.frame(width: 0, height: 0))
        .onDisappear { model.execution.cancel() }
        .task(id: model.startupRoute) {
            if model.takeUpdateHistoryPresentation() { openWindow(id: "release-history") }
        }
        .alert("codelib", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("Понятно") { model.message = nil }
            if let message = model.message, message.diagnostics != nil {
                Button("Скопировать диагностику") { message.copyDiagnostics() }
            }
        } message: {
            if let message = model.message { Text(message.resource()) }
        }
    }

    private var workspace: some View {
        NavigationSplitView {
            List(selection: $model.page) {
                Section("Пространство") {
                    navigationRow(.home)
                    navigationRow(.catalog)
                }
                Section("Практика") {
                    navigationRow(.syllabus)
                    navigationRow(.lesson)
                }
                Section("Ваш результат") {
                    navigationRow(.progress)
                    navigationRow(.achievements)
                }
            }.listStyle(.sidebar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 38, height: 38)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("codelib").font(.system(size: 24, weight: .bold, design: .rounded)).tracking(-1)
                        Text("Лаборатория кода").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 24)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 290)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 18) {
                    if let course = model.course {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("ВАШ C++").font(.system(size: 10, weight: .bold)).tracking(1.5)
                                Spacer()
                                Text(model.fraction, format: PresentationLocale.percent).monospacedDigit()
                            }.foregroundStyle(.secondary)
                            ProgressView(value: model.fraction).tint(.green)
                            Text("\(model.document.completedCount(in: course)) из \(course.exercises.count) заданий")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    SettingsLink {
                        HStack(spacing: 10) {
                            if let profile = model.document.profile { ProfileAvatar(profile: profile, size: 32) }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(model.document.profile?.nickname ?? "Ваш профиль").font(.headline).lineLimit(1)
                                Text("Профиль и настройки").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "gearshape").foregroundStyle(.secondary)
                        }.foregroundStyle(Color.primary).padding(12).contentShape(RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain).modifier(WorkspaceGlass())
                }.padding(16)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .onChange(of: model.page) { _, page in
                if page == .lesson && model.exercise == nil { model.resume() }
            }
        } detail: {
            VStack(spacing: 0) {
                if model.hasUnsavedChanges {
                    HStack {
                        Label {
                            if let error = model.saveError { Text("Не сохранено: \(String(localized: error.resource()))") }
                            else { Text("Не сохранено: идёт запись") }
                        } icon: { Image(systemName: "exclamationmark.triangle") }
                        Spacer()
                        Button("Повторить") { model.flush() }
                        Button("Экспорт") { model.exportProgress() }
                        if let error = model.saveError, error.diagnostics != nil {
                            Button("Скопировать диагностику") { error.copyDiagnostics() }
                        }
                    }.font(.caption).padding(10).background(.orange.opacity(0.15))
                }
                Group {
                    switch model.page {
                    case .home: HomeView(model: model)
                    case .catalog: CatalogView(model: model)
                    case .syllabus: SyllabusView(model: model)
                    case .lesson: LessonView(model: model)
                    case .progress: ProgressViewScreen(model: model)
                    case .achievements: AchievementCollectionView(model: model)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                AchievementBanner(model: model)
            }.background(WorkspaceBackdrop())
            .navigationTitle(Text(model.page.title))
            .toolbar {
                if model.page != .lesson {
                    ToolbarItem {
                        Label("На вашем Mac", systemImage: "internaldrive")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ToolbarItem { Button("Продолжить", systemImage: "arrow.right.circle") { model.resume() } }
                }
            }
        }
    }

    private func navigationRow(_ page: AppModel.Page) -> some View {
        Label {
            Text(page.title).font(.system(size: 14, weight: model.page == page ? .semibold : .medium))
        } icon: {
            Image(systemName: page.icon).symbolVariant(model.page == page ? .fill : .none)
                .foregroundStyle(model.page == page ? Color.green : .secondary)
        }.padding(.vertical, 7).tag(page)
    }
}

struct PageHeader: View {
    let eyebrow: LocalizedStringResource
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(PresentationLocale.resource(eyebrow)).textCase(.uppercase).font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.tint)
            Text(PresentationLocale.resource(title)).font(.system(size: 32, weight: .bold)).tracking(-0.8)
            Text(PresentationLocale.resource(subtitle)).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.primary.opacity(0.07)) }
    }
}

/// Static, inexpensive color wash; readable content surfaces remain opaque.
struct WorkspaceBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .overlay(alignment: .topTrailing) {
                RadialGradient(colors: [.green.opacity(scheme == .dark ? 0.075 : 0.05), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 650)
            }.ignoresSafeArea()
    }
}

struct WorkspaceGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        } else {
            content
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
