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
        VStack(spacing: 22) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().frame(width: 112, height: 112).accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("codelib").font(.system(size: 34, weight: .bold, design: .rounded)).tracking(-1)
                Text("Лаборатория кода").font(.callout).foregroundStyle(.secondary)
            }
            ReleaseVersionLabel(release: model.appRelease).font(.callout)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.primary.opacity(0.05), in: Capsule())
            Text("Нативная лаборатория программирования.\nПрактический курс C++ для macOS — офлайн, без аккаунтов и телеметрии.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("История обновлений", systemImage: "clock.arrow.circlepath") { openWindow(id: "release-history") }
                .buttonStyle(.bordered).controlSize(.large)
            Text("C++17 запускается в одноразовой изолированной среде. Кодовые задания проверяются на примерах из условия; AI нет.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(36).frame(minWidth: 460, minHeight: 430).background(WorkspaceBackdrop())
    }
}

struct ReleaseHistoryView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var acknowledgementFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("ЧТО НОВОГО В CODELIB").font(.system(size: 10, weight: .bold)).tracking(1.6).foregroundStyle(.green)
                Text("История обновлений").font(.system(size: 28, weight: .bold)).tracking(-0.7)
                ReleaseVersionLabel(release: model.appRelease).font(.callout).foregroundStyle(.secondary)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let history = model.releaseHistory {
                        ForEach(history.releases.filter { note in
                            model.appRelease.map { note.version <= $0.version } ?? true
                        }) { note in
                            releaseCard(note)
                        }
                    } else {
                        ContentUnavailableView("История недоступна", systemImage: "exclamationmark.triangle",
                                               description: Text(model.releaseHistoryError.map { $0.resource(locale: model.presentationLocale) } ?? PresentationLocale.resource("Не удалось загрузить ресурс", locale: model.presentationLocale)))
                        if let failure = model.releaseHistoryError { FailureDiagnostics(failure: failure) }
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                if acknowledgementFailed {
                    FailureText(failure: model.saveError ?? model.storageError, fallback: "Не удалось сохранить отметку просмотра.", locale: model.presentationLocale)
                        .font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
                Spacer()
                Button("Закрыть") { dismiss() }
                Button {
                    guard let release = model.appRelease else { return }
                    if model.markReleaseViewed(release.version) { dismiss() }
                    else { acknowledgementFailed = true }
                } label: {
                    if acknowledgementFailed { Text("Повторить сохранение") }
                    else { Text("Отметить прочитанным") }
                }
                .disabled(model.appRelease == nil || model.releaseHistory == nil)
                .buttonStyle(.borderedProminent)
            }.padding(20)
        }.frame(minWidth: 560, minHeight: 480).background(WorkspaceBackdrop())
    }

    private func releaseCard(_ note: ReleaseNote) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(note.version.rawValue).font(.system(size: 24, weight: .bold, design: .rounded)).tracking(-0.5)
                    if let stage = note.stage {
                        Text(stage.rawValue).font(.caption.weight(.semibold)).foregroundStyle(.green)
                            .padding(.horizontal, 10).padding(.vertical, 4).background(Color.green.opacity(0.1), in: Capsule())
                    }
                    Spacer()
                    if let date = note.date { Text(PresentationLocale.releaseDate(date, locale: model.presentationLocale)).font(.caption).foregroundStyle(.secondary) }
                }
                Text(note.title).font(.title3.weight(.semibold))
                Text(note.summary).fixedSize(horizontal: false, vertical: true)
                ForEach(note.features) { feature in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: feature.symbol).font(.title3).foregroundStyle(.green)
                            .frame(width: 34, height: 34).background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityHidden(true)
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
            }.textSelection(.enabled)
        }
    }
}
