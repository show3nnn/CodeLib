import SwiftUI
import LearningCore

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if let error = model.contentError {
                ContentUnavailableView("Не удалось загрузить курс", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if let error = model.storageError {
                VStack(spacing: 20) {
                    ContentUnavailableView("Прогресс не открыт", systemImage: "externaldrive.badge.exclamationmark",
                                           description: Text(error + "\nИсходный файл не изменён. Можно восстановить предыдущую сохранённую версию из резервной копии."))
                    Text(model.dataURL.path).font(.caption).textSelection(.enabled)
                    Button("Восстановить резервную копию") { model.restoreBackup() }
                    Text("Перед восстановлением исходный файл будет сохранён отдельно. Если резервной копии нет, операция ничего не изменит.")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: 520)
                }.padding()
            } else {
                workspace
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .alert("codelib", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("Понятно") { model.message = nil }
        } message: { Text(model.message ?? "") }
    }

    private var workspace: some View {
        NavigationSplitView {
            List(selection: $model.page) {
                Section("codelib") {
                    ForEach(AppModel.Page.allCases) { page in
                        Label(page.title, systemImage: page.icon).tag(page)
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
                        Label("Не сохранено: \(model.saveError ?? "идёт запись")", systemImage: "exclamationmark.triangle")
                        Spacer()
                        Button("Повторить") { model.flush() }
                        Button("Экспорт") { model.exportProgress() }
                    }.font(.caption).padding(10).background(.orange.opacity(0.15))
                }
                Group {
                    switch model.page {
                    case .home: HomeView(model: model)
                    case .catalog: CatalogView(model: model)
                    case .syllabus: SyllabusView(model: model)
                    case .lesson: LessonView(model: model)
                    case .progress: ProgressViewScreen(model: model)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(model.page.title)
            .toolbar {
                if model.page != .lesson {
                    ToolbarItem { Button("Продолжить", systemImage: "arrow.right.circle") { model.resume() } }
                }
            }
        }
    }
}

struct PageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow.uppercased()).font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.tint)
            Text(title).font(.largeTitle.bold())
            Text(subtitle).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
