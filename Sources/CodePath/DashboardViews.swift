import SwiftUI
import LearningCore

struct HomeView: View {
    @Bindable var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .center, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ВАША ЛАБОРАТОРИЯ").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(.green)
                        Text(model.document.profile.map { "С возвращением, \($0.nickname)." } ?? "Хороший день для кода.")
                            .font(.system(size: 30, weight: .bold)).tracking(-0.8)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Один понятный шаг. Ещё немного собственного кода.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if let profile = model.document.profile { ProfileAvatar(profile: profile, size: 54) }
                }
                if let course = model.course {
                    courseHero(course)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 14) {
                        Metric(value: "\(model.document.completedCount(in: course))", label: "заданий завершено", icon: "checkmark.circle")
                        Metric(value: "\(course.lessons.filter { model.document.lessonCompleted($0) }.count)", label: "уроков завершено", icon: "book.closed")
                        Metric(value: "\(AchievementCatalog.all.filter { model.document.achievements?.awards[$0.id] != nil }.count)", label: "достижений", icon: "trophy")
                    }
                    HStack {
                        Text("Следующий шаг").font(.system(size: 21, weight: .bold)).tracking(-0.4)
                        Spacer()
                        Button("Вся программа", systemImage: "arrow.up.right") { model.page = .syllabus }.buttonStyle(.plain).foregroundStyle(.green)
                    }
                    if let lesson = model.lesson ?? course.lessons.first {
                        Button { model.openLesson(lesson) } label: {
                            Card {
                                HStack(spacing: 18) {
                                    Image(systemName: "arrow.turn.down.right").font(.title2).foregroundStyle(.green)
                                        .frame(width: 48, height: 48).background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(lesson.title).font(.headline)
                                        Text(lesson.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                                        Text("\(lesson.exercises.count) заданий · ~\(lesson.minutes) мин")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "arrow.right").foregroundStyle(.green)
                                }
                            }.contentShape(RoundedRectangle(cornerRadius: 22))
                        }.buttonStyle(.plain).accessibilityHint("Открыть урок с сохранённого задания")
                    }
                    RecentAchievementsView(model: model)
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                        Text("Ваш темп. Ваши данные. Всё остаётся на этом Mac.")
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }.padding(32).frame(maxWidth: 1120).frame(maxWidth: .infinity)
        }
    }

    private func courseHero(_ course: Course) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack {
                Label("АКТИВНЫЙ КУРС", systemImage: "circle.fill")
                    .font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(.mint)
                Spacer()
                Text("C++17 / C++20").font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 28) {
                    heroIntroduction.frame(minWidth: 300, maxWidth: .infinity, alignment: .leading)
                    CourseArtwork().frame(width: 210, height: 170).accessibilityHidden(true)
                }
                heroIntroduction
            }
            Divider().overlay(.white.opacity(0.12))
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Прогресс курса").foregroundStyle(.white.opacity(0.65))
                        Spacer()
                        Text(model.fraction, format: PresentationLocale.percent).foregroundStyle(.mint).monospacedDigit()
                    }.font(.caption.weight(.medium))
                    ProgressView(value: model.fraction).tint(.mint)
                    Text("\(course.sections.count) разделов · \(course.lessons.count) уроков · \(course.exercises.count) заданий")
                        .font(.caption).foregroundStyle(.white.opacity(0.55))
                }
            }
        }.padding(28)
            .background {
                RoundedRectangle(cornerRadius: 26).fill(Color(red: 0.055, green: 0.085, blue: 0.075))
                    .overlay(alignment: .topTrailing) {
                        RadialGradient(colors: [.green.opacity(0.18), .clear], center: .topTrailing, startRadius: 0, endRadius: 420)
                    }.clipShape(RoundedRectangle(cornerRadius: 26))
            }
            .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.10)) }
    }

    private var heroIntroduction: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("C++ с нуля.\nДо своего проекта.")
                .font(.system(size: 37, weight: .semibold)).tracking(-1.2).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if let course = model.course {
                let section = course.sections.first { section in section.lessons.contains { $0.id == model.lesson?.id } }
                Text(section?.title ?? "От первой строки к самостоятельному коду")
                    .font(.callout).foregroundStyle(.white.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
            }
            Button { model.resume() } label: {
                Label("Продолжить обучение", systemImage: "arrow.right").font(.headline)
                    .foregroundStyle(.black).padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Color.mint, in: Capsule())
                    .contentShape(Capsule())
            }.buttonStyle(.plain)
                .accessibilityIdentifier("home.resume")
        }
    }
}

private struct CourseArtwork: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 6) {
                ForEach(0..<3) { _ in Circle().fill(.white.opacity(0.18)).frame(width: 5, height: 5) }
                Spacer()
                Text("hello.cpp").font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.45))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("int main() {").foregroundStyle(.white.opacity(0.9))
                Text("  // Начни здесь").foregroundStyle(.white.opacity(0.4))
                Text("  std::cout").foregroundStyle(.mint)
                Text("    << \"Hello!\";").foregroundStyle(.white.opacity(0.9))
                Text("}").foregroundStyle(.mint)
            }.font(.system(size: 14, weight: .medium, design: .monospaced))
        }.padding(20).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12)) }
            .rotationEffect(.degrees(-3))
    }
}
struct Metric: View {
    let value: String
    let label: LocalizedStringResource
    let icon: String
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon).foregroundStyle(.green)
                    Spacer()
                    Text(value).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                Text(PresentationLocale.resource(label)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct FutureCourses: View {
    let entries: [CourseListing]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("На горизонте").font(.title2.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 12) {
                ForEach(entries) { entry in
                    Card {
                        VStack(alignment: .leading, spacing: 20) {
                            HStack {
                                Text(entry.language == "JavaScript" ? "JS" : String(entry.language.prefix(2)))
                                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: "lock").font(.caption).foregroundStyle(.tertiary)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.title).font(.headline)
                                Text("Скоро").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            }
                        }
                    }.accessibilityElement(children: .combine)
                }
            }
        }
    }
}

struct CatalogView: View {
    @Bindable var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageHeader(eyebrow: "Каталог курсов", title: "Большие идеи начинаются\nс первой строки.", subtitle: "Выберите своё направление. Учитесь в собственном темпе.")
                Card {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .top, spacing: 20) {
                            Image(systemName: "curlybraces").font(.system(size: 40, weight: .medium))
                                .foregroundStyle(.green).frame(width: 84, height: 84)
                                .background(.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 22))
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Доступен сейчас", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.medium)).foregroundStyle(.green)
                                Text("C++").font(.system(size: 34, weight: .bold)).tracking(-1)
                                Text("С нуля до своего проекта").font(.title3.weight(.medium))
                            }
                        }
                        Text(model.course?.summary ?? "").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if let course = model.course {
                            Text("\(course.sections.count) разделов  /  \(course.lessons.count) уроков  /  \(course.exercises.count) заданий")
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) { catalogActions }
                            VStack(alignment: .leading, spacing: 12) { catalogActions }
                        }
                    }
                }
                FutureCourses(entries: model.catalog?.entries.filter { $0.availability == .comingSoon } ?? [])
            }.padding(32).frame(maxWidth: 1040).frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var catalogActions: some View {
        Button("Продолжить обучение", systemImage: "arrow.right") { model.resume() }
            .buttonStyle(.borderedProminent).controlSize(.large)
        Button("Изучить программу", systemImage: "list.bullet") { model.page = .syllabus }
            .buttonStyle(.bordered).controlSize(.large)
    }
}

struct SyllabusView: View {
    @Bindable var model: AppModel
    @State private var search = ""
    @State private var status: LessonStatusFilter = .all
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                PageHeader(eyebrow: "C++17 · практика", title: "Шаги к самостоятельному коду", subtitle: "Все доступные темы открыты. Возвращайтесь к теории и задачам без потери результатов.")
                if let course = model.course {
                    Picker("Состояние урока", selection: $status) {
                        Text("Все").tag(LessonStatusFilter.all)
                        Text("Не начаты").tag(LessonStatusFilter.notStarted)
                        Text("В работе").tag(LessonStatusFilter.inProgress)
                        Text("Завершены").tag(LessonStatusFilter.completed)
                    }.pickerStyle(.segmented)
                    let sections = course.studySections(query: search, status: status, progress: model.document)
                    ForEach(sections) { group in
                        let section = group.section
                        let lessons = group.lessons
                            Card {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text(section.title).font(.title2.bold())
                                    Text(section.summary).foregroundStyle(.secondary)
                                    ForEach(lessons) { lesson in
                                        Button {
                                            model.openLesson(lesson)
                                        } label: {
                                            HStack(spacing: 14) {
                                                Image(systemName: model.document.lessonCompleted(lesson) ? "checkmark.circle.fill" : "circle")
                                                    .foregroundStyle(model.document.lessonCompleted(lesson) ? Color.green : Color.secondary)
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(lesson.title).font(.headline)
                                                    Text(lesson.summary).font(.caption).foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                Text("\(lesson.exercises.filter { model.document.completed($0.id) }.count)/\(lesson.exercises.count) · ~\(lesson.minutes) мин")
                                                    .font(.caption).foregroundStyle(.secondary)
                                                Image(systemName: "chevron.right").font(.caption)
                                            }.padding(.vertical, 8).contentShape(Rectangle())
                                        }.buttonStyle(.plain)
                                        if lesson.id != lessons.last?.id { Divider() }
                                    }
                                }
                            }
                    }
                    if sections.isEmpty {
                        ContentUnavailableView("Уроки не найдены", systemImage: "line.3.horizontal.decrease.circle",
                                               description: Text("Измените запрос или фильтр состояния."))
                        Button("Сбросить поиск и фильтр") { search = ""; status = .all }
                    }
                }
            }.padding(32).frame(maxWidth: 1080).frame(maxWidth: .infinity)
        }.searchable(text: $search, prompt: "Тема, раздел, задание или навык")
    }
}

struct ProgressViewScreen: View {
    @Bindable var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(eyebrow: "Ваш путь", title: "Знания складываются из практики", subtitle: "Автоматическая проверка и самостоятельные отметки учитываются отдельно.")
                if let course = model.course {
                    let finished = course.exercises.filter { model.document.completed($0.id) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170))], spacing: 16) {
                        Metric(value: "\(finished.filter { model.state(for: $0.id).completion == .automatic }.count)", label: "проверено автоматически", icon: "checkmark.seal")
                        Metric(value: "\(finished.filter { model.state(for: $0.id).completion == .selfReviewed }.count)", label: "отмечено вами", icon: "person.crop.circle.badge.checkmark")
                        Metric(value: "\(course.exercises.count - finished.count)", label: "впереди", icon: "arrow.forward.circle")
                        Metric(value: "\(AchievementCatalog.all.filter { model.document.achievements?.awards[$0.id] != nil }.count)", label: "достижений", icon: "trophy")
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Продолжить с последнего места").font(.headline)
                            if let lesson = model.lesson {
                                Text(verbatim: lesson.title)
                            } else {
                                Text("Первый урок")
                            }
                            if let date = model.document.lastStudyDate {
                                Text("Последнее занятие: \(PresentationLocale.date(date, includeTime: true))").foregroundStyle(.secondary)
                            }
                            Button("Вернуться к заданию") { model.resume() }.buttonStyle(.borderedProminent)
                        }
                    }
                    Text("Стоит повторить").font(.title2.bold())
                    let review = course.exercises.filter {
                        let state = model.state(for: $0.id)
                        return state.lastCorrect == false || state.hintLevel >= 2
                    }
                    if review.isEmpty {
                        Text("Здесь появятся задания с ошибками или раскрытыми подробными подсказками.").foregroundStyle(.secondary)
                    } else {
                        ForEach(review) { task in
                            Button { model.open(task) } label: {
                                Label(task.title, systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            }.buttonStyle(.bordered)
                        }
                    }
                    Text("По разделам").font(.title2.bold())
                    ForEach(course.sections) { section in
                        let tasks = section.lessons.flatMap(\.exercises)
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(section.title).font(.headline)
                                ProgressView(value: Double(tasks.filter { model.document.completed($0.id) }.count), total: Double(tasks.count))
                                Text("\(tasks.filter { model.document.completed($0.id) }.count) из \(tasks.count)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }.padding(32).frame(maxWidth: 1080).frame(maxWidth: .infinity)
        }
    }
}
