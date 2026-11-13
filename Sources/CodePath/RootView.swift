import SwiftUI
import LearningCore

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
                if let profile = model.document.profile {
                    HStack {
                        ProfileAvatar(profile: profile, size: 34)
                        Text(profile.nickname).font(.headline)
                    }.padding(.vertical, 6)
                }
                Section("codelib") {
                    ForEach(AppModel.Page.allCases) { page in
                        Label { Text(page.title) } icon: { Image(systemName: page.icon) }.tag(page)
                    }
                }
                if let course = model.course {
                    Section("Учиться в своём темпе") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("C++ · первый курс").font(.headline)
                            ProgressView(value: model.fraction)
                            Text("\(model.document.completedCount(in: course)) из \(course.exercises.count) заданий")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Офлайн · только на вашем Mac").font(.caption2).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
            .safeAreaInset(edge: .bottom) {
                SettingsLink { Label("Настройки", systemImage: "gearshape") }
                    .buttonStyle(.plain).padding().frame(maxWidth: .infinity, alignment: .leading)
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
            }
            .navigationTitle(Text(model.page.title))
            .toolbar {
                if model.page != .lesson {
                    ToolbarItem { Button("Продолжить", systemImage: "arrow.right.circle") { model.resume() } }
                }
            }
        }
    }
}

struct PageHeader: View {
    let eyebrow: LocalizedStringResource
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(PresentationLocale.resource(eyebrow)).textCase(.uppercase).font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.tint)
            Text(PresentationLocale.resource(title)).font(.largeTitle.bold())
            Text(PresentationLocale.resource(subtitle)).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.08)) }
    }
}
