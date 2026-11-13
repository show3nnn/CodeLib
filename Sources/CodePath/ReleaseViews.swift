import AppKit
import LearningCore
import SwiftUI

struct ReleaseVersionLabel: View {
    let release: AppRelease?
    var body: some View {
        if let release {
            Text("\(release.display) · сборка \(release.build)")
                .textSelection(.enabled)
        } else {
            Text("Метаданные версии недоступны").foregroundStyle(.secondary)
        }
    }
}

struct AboutView: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().frame(width: 112, height: 112).accessibilityHidden(true)
            Text("codelib").font(.largeTitle.bold())
            ReleaseVersionLabel(release: model.appRelease).font(.callout)
            Text("Нативная лаборатория программирования")
            Text("Практический курс C++ для macOS.\nОфлайн, без аккаунтов и телеметрии.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("История обновлений") { openWindow(id: "release-history") }
            Text("Код сохраняется как черновик; встроенного исполнения и AI нет.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(32).frame(minWidth: 440, minHeight: 400)
    }
}

struct ReleaseHistoryView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var acknowledgementFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Что нового в codelib").font(.largeTitle.bold())
                ReleaseVersionLabel(release: model.appRelease).foregroundStyle(.secondary)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let history = model.releaseHistory {
                        ForEach(history.releases.filter { note in
                            model.appRelease.map { note.version <= $0.version } ?? true
                        }) { note in
                            releaseCard(note)
                        }
                    } else {
                        ContentUnavailableView("История недоступна", systemImage: "exclamationmark.triangle",
                                               description: Text(model.releaseHistoryError.map { $0.resource() } ?? PresentationLocale.resource("Не удалось загрузить ресурс")))
                        if let failure = model.releaseHistoryError { FailureDiagnostics(failure: failure) }
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                if acknowledgementFailed {
                    FailureText(failure: model.saveError ?? model.storageError, fallback: "Не удалось сохранить отметку просмотра.")
                        .font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
                Spacer()
                Button("Закрыть") { dismiss() }
                Button(acknowledgementFailed ? "Повторить сохранение" : "Отметить прочитанным") {
                    guard let release = model.appRelease else { return }
                    if model.markReleaseViewed(release.version) { dismiss() }
                    else { acknowledgementFailed = true }
                }
                .disabled(model.appRelease == nil || model.releaseHistory == nil)
                .buttonStyle(.borderedProminent)
            }.padding(20)
        }.frame(minWidth: 560, minHeight: 480)
    }

    private func releaseCard(_ note: ReleaseNote) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(note.version.rawValue)\(note.stage.map { " · " + $0.rawValue } ?? "")")
                .font(.title2.bold())
            if let date = note.date { Text(date).font(.caption).foregroundStyle(.secondary) }
            Text(note.title).font(.title3.bold())
            Text(note.summary).fixedSize(horizontal: false, vertical: true)
            ForEach(note.features) { feature in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: feature.symbol).font(.title2).foregroundStyle(.tint)
                        .frame(width: 32).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(feature.title).font(.headline)
                        Text(feature.detail).foregroundStyle(.secondary)
                    }
                }
            }
            if !note.improvements.isEmpty {
                Text("Улучшения").font(.headline)
                ForEach(note.improvements, id: \.self) { Text("• " + $0) }
            }
            if !note.fixes.isEmpty {
                Text("Исправления").font(.headline)
                ForEach(note.fixes, id: \.self) { Text("• " + $0) }
            }
            Divider()
        }.textSelection(.enabled)
    }
}
