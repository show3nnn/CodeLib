import AppKit
import LearningCore
import SwiftUI

// UI resources stay in the presentation layer; LearningCore has no SwiftUI dependency.
extension AchievementCategory {
    var localizedTitle: LocalizedStringResource {
        let result: LocalizedStringResource = switch self {
        case .firstSteps: "Первые шаги"
        case .practice: "Практика"
        case .algorithms: "Алгоритмы"
        case .persistence: "Настойчивость"
        case .exploration: "Исследование"
        case .mastery: "Мастерство"
        }
        return PresentationLocale.resource(result)
    }
}

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
                PageHeader(eyebrow: "Коллекция", title: "Не только точки с запятой", subtitle: "Награды за настоящую практику. Самостоятельная отметка сама по себе не означает запуск или проверку кода.", locale: model.presentationLocale)
                let unlocked = AchievementCatalog.all.filter { model.document.achievements?.awards[$0.id] != nil }.count
                Card {
                    HStack(spacing: 24) {
                        ZStack {
                            Circle().stroke(.green.opacity(0.1), lineWidth: 7)
                            Circle().trim(from: 0, to: Double(unlocked) / Double(AchievementCatalog.all.count))
                                .stroke(.green, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                            Text("\(unlocked)/\(AchievementCatalog.all.count)").font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                        }.frame(width: 76, height: 76)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Прогресс коллекции")
                            .accessibilityValue(Text("Открыто \(unlocked) из \(AchievementCatalog.all.count)"))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Коллекция наград").font(.caption.weight(.semibold)).foregroundStyle(.green)
                            Text("Открыто \(unlocked) из \(AchievementCatalog.all.count)").font(.system(size: 24, weight: .semibold, design: .rounded)).tracking(-0.4)
                            Group {
                                if unlocked == 0 { Text("Первая награда появится за настоящую практику.") }
                                else { Text("Каждая награда выдаётся один раз и сохраняется в профиле.") }
                            }.font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Picker("Категория", selection: $category) {
                            Text("Все категории").tag(AchievementCategory?.none)
                            ForEach(AchievementCategory.allCases, id: \.self) { Text(PresentationLocale.resource($0.localizedTitle, locale: model.presentationLocale)).tag(Optional($0)) }
                        }.pickerStyle(.menu).labelsHidden().frame(maxWidth: 220)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                    ForEach(AchievementCatalog.all.filter { category == nil || $0.category == category }) { item in
                        let earned = model.document.achievements?.awards[item.id]
                        let hidden = item.secret && earned == nil
                        Button { selected = item.id } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                Image(systemName: hidden ? "questionmark.diamond" : item.symbol)
                                    .font(.title).foregroundStyle(earned == nil ? Color.secondary : .green)
                                    .frame(width: 44, height: 44)
                                    .background(earned == nil ? Color.primary.opacity(0.05) : Color.green.opacity(0.1),
                                                in: RoundedRectangle(cornerRadius: 13))
                                Group {
                                    if hidden { Text("Секретное достижение") }
                                    else { Text(verbatim: item.title(locale: model.presentationLanguage)) }
                                }.font(.headline)
                                Group {
                                    if hidden { Text("Найдётся во время практики.") }
                                    else { Text(verbatim: item.detail(locale: model.presentationLanguage)) }
                                }.font(.callout).foregroundStyle(.secondary)
                                if let earned {
                                    Group {
                                        if earned.historical {
                                            Text("Учтено из прежнего прогресса · \(PresentationLocale.date(earned.recognizedAt, locale: model.presentationLocale))")
                                        } else {
                                            Text("Получено · \(PresentationLocale.date(earned.recognizedAt, locale: model.presentationLocale))")
                                        }
                                    }.font(.caption).foregroundStyle(.secondary)
                                } else if !hidden, let course = model.course {
                                    let value = min(item.target, AchievementEngine.value(for: item, document: model.document, course: course))
                                    ProgressView(value: Double(value), total: Double(item.target)).tint(.green)
                                    Text("\(value) / \(item.target)").font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(20).frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
                                .background(.background, in: RoundedRectangle(cornerRadius: 18))
                                .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(earned == nil ? Color.primary.opacity(0.08) : Color.green.opacity(0.45)) }
                                .contentShape(RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(28).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }
        .sheet(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            if let item = AchievementCatalog.all.first(where: { $0.id == selected }) {
                let hidden = item.secret && model.document.achievements?.awards[item.id] == nil
                VStack(spacing: 18) {
                    Image(systemName: hidden ? "questionmark.diamond" : item.symbol)
                        .font(.system(size: 28, weight: .medium)).foregroundStyle(.green)
                        .frame(width: 72, height: 72).background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
                    Group {
                        if hidden { Text("Секретное достижение") }
                        else { Text(verbatim: item.title(locale: model.presentationLanguage)) }
                    }.font(.title2.bold())
                    Group {
                        if hidden { Text("Условие откроется после получения награды.") }
                        else { Text(verbatim: item.detail(locale: model.presentationLanguage)) }
                    }.multilineTextAlignment(.center)
                    Text("Награда выдаётся один раз и сохраняется в локальном профиле.").font(.caption).foregroundStyle(.secondary)
                    Button("Закрыть") { selected = nil }.buttonStyle(.borderedProminent)
                }.padding(32).frame(width: 440)
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
                        Text("Новое достижение · \(award.title(locale: model.presentationLanguage))").font(.headline)
                        Text(verbatim: award.detail(locale: model.presentationLanguage)).font(.caption).foregroundStyle(.secondary)
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
                        Label { Text(verbatim: award.title(locale: model.presentationLanguage)) } icon: { Image(systemName: award.symbol) }.foregroundStyle(.green)
                    }
                }
            }
        }
    }
}
