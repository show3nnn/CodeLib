import AppKit
import LearningCore
import SwiftUI

@MainActor
enum AchievementAudio {
    private static var active: NSSound?
    @discardableResult static func play(enabled: Bool) -> Bool {
        guard enabled, let url = AchievementCatalog.soundURL, let sound = NSSound(contentsOf: url, byReference: true) else { return false }
        active?.stop()
        active = sound
        return sound.play()
    }
}

struct AchievementCollectionView: View {
    @Bindable var model: AppModel
    @State private var category: AchievementCategory?
    @State private var selected: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(eyebrow: "Коллекция", title: "Не только точки с запятой", subtitle: "Награды за настоящую практику. Самостоятельные отметки не выдаются за запуск или проверку C++.")
                let unlocked = AchievementCatalog.all.filter { model.document.achievements?.awards[$0.id] != nil }.count
                HStack {
                    Text("Открыто \(unlocked) из \(AchievementCatalog.all.count)").font(.headline)
                    Spacer()
                    ProgressView(value: Double(unlocked), total: Double(AchievementCatalog.all.count)).frame(maxWidth: 180)
                }
                Picker("Категория", selection: $category) {
                    Text("Все категории").tag(AchievementCategory?.none)
                    ForEach(AchievementCategory.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                }.frame(maxWidth: 320)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                    ForEach(AchievementCatalog.all.filter { category == nil || $0.category == category }) { item in
                        let earned = model.document.achievements?.awards[item.id]
                        let hidden = item.secret && earned == nil
                        Button { selected = item.id } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                Image(systemName: hidden ? "questionmark.diamond" : item.symbol)
                                    .font(.title).foregroundStyle(earned == nil ? Color.secondary : .green)
                                Text(hidden ? "Секретное достижение" : item.title()).font(.headline)
                                Text(hidden ? "Найдётся во время практики." : item.detail()).font(.callout).foregroundStyle(.secondary)
                                if let earned {
                                    Text((earned.historical ? "Учтено из прежнего прогресса · " : "Получено · ") + earned.recognizedAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption).foregroundStyle(.secondary)
                                } else if !hidden, let course = model.course {
                                    let value = min(item.target, AchievementEngine.value(for: item, document: model.document, course: course))
                                    ProgressView(value: Double(value), total: Double(item.target))
                                    Text("\(value) / \(item.target)").font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(20).frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
                                .background(.background, in: RoundedRectangle(cornerRadius: 18))
                                .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(earned == nil ? Color.primary.opacity(0.08) : Color.green.opacity(0.45)) }
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(28).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }
        .sheet(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            if let item = AchievementCatalog.all.first(where: { $0.id == selected }) {
                let hidden = item.secret && model.document.achievements?.awards[item.id] == nil
                VStack(spacing: 18) {
                    Image(systemName: hidden ? "questionmark.diamond" : item.symbol).font(.largeTitle).foregroundStyle(.green)
                    Text(hidden ? "Секретное достижение" : item.title()).font(.title2.bold())
                    Text(hidden ? "Условие откроется после получения награды." : item.detail()).multilineTextAlignment(.center)
                    Text("Награда выдаётся один раз и сохраняется в локальном профиле.").font(.caption).foregroundStyle(.secondary)
                    Button("Закрыть") { selected = nil }
                }.padding(32).frame(width: 420)
            }
        }
    }
}

struct AchievementBanner: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 0) {
            if let id = model.achievementNotifications.first, let award = AchievementCatalog.all.first(where: { $0.id == id }) {
                HStack(spacing: 14) {
                    Image(systemName: award.symbol).font(.title2).foregroundStyle(.green).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Новое достижение · " + award.title()).font(.headline)
                        Text(award.detail()).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Коллекция") { model.page = .achievements; model.achievementNotifications.removeAll() }
                    Button {
                        if model.achievementNotifications.first == id { model.achievementNotifications.removeFirst() }
                    } label: { Image(systemName: "xmark") }
                        .help("Закрыть уведомление").accessibilityLabel("Закрыть уведомление")
                }.padding(14).glassEffect(.regular.tint(.green.opacity(0.08)), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .task(id: id) {
                        _ = AchievementAudio.play(enabled: model.document.preferences.achievementSounds)
                        do {
                            try await Task.sleep(for: .seconds(5))
                            if model.achievementNotifications.first == id { model.achievementNotifications.removeFirst() }
                        } catch { /* Dismiss/navigation cancels the banner timer. */ }
                    }
                    .transition(reduceMotion ? .identity : .opacity)
            }
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.achievementNotifications.first)
    }
}

struct RecentAchievementsView: View {
    let model: AppModel
    var body: some View {
        let awards = model.document.achievements?.awards ?? [:]
        let recent = AchievementCatalog.all.filter { awards[$0.id] != nil }.sorted {
            let left = awards[$0.id]!.recognizedAt, right = awards[$1.id]!.recognizedAt
            return left == right ? $0.id < $1.id : left > right
        }
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Недавние достижения", systemImage: "trophy").font(.headline)
                    Spacer()
                    Button("Все награды") { model.page = .achievements }
                }
                if recent.isEmpty {
                    Text("Первая награда появится за настоящую практику. Коллекция уже доступна.").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(recent.prefix(3))) { award in
                        Label(award.title(), systemImage: award.symbol).foregroundStyle(.green)
                    }
                }
            }
        }
    }
}
