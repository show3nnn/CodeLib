import SwiftUI
import LearningCore

struct HomeView: View {
    @Bindable var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageHeader(eyebrow: "Ваша лаборатория кода", title: model.document.profile.map { "С возвращением, \($0.nickname)!" } ?? "Хороший день, чтобы разобраться.",
                           subtitle: "Немного теории. Много собственного кода. Один понятный шаг за другим.")
                if let course = model.course {
                    Card {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack(alignment: .top) {
                                Image(systemName: "curlybraces").font(.system(size: 38, weight: .medium)).foregroundStyle(.tint)
                                    .frame(width: 76, height: 76).background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("C++").font(.title.bold())
                                    Text("С нуля до уверенного первого курса").font(.title3)
                                    Text("Сейчас: \(model.lesson?.title ?? course.lessons.first?.title ?? "")").foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            ProgressView(value: model.fraction)
                            HStack {
                                Text(model.fraction, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                                Text("доступного курса пройдено").foregroundStyle(.secondary)
                                Spacer()
                                Button("Продолжить обучение", systemImage: "arrow.right") { model.resume() }
                                    .buttonStyle(.borderedProminent).controlSize(.large)
                            }
                        }
                    }
                    HStack(spacing: 16) {
                        Metric(value: "\(course.lessons.filter { model.document.lessonCompleted($0) }.count)", label: "уроков завершено", icon: "book.closed")
                        Metric(value: "\(model.document.completedCount(in: course))", label: "заданий завершено", icon: "checkmark.circle")
                        Metric(value: "\(course.sections.count)", label: "доступных разделов", icon: "square.stack")
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("От первой строки до своего проекта", systemImage: "leaf").font(.headline)
                            Text("Доступно: \(course.sections.count) разделов, \(course.lessons.count) уроков, \(course.exercises.count) заданий. Код, теория, контрольные и мини-проекты — от main до файлов и итогового диспетчера запасов. Все результаты остаются на вашем Mac.")
                                .foregroundStyle(.secondary)
                            Button("Открыть программу") { model.page = .syllabus }
                        }
                    }
                    FutureCourses(entries: model.catalog?.entries.filter { $0.availability == .comingSoon } ?? [])
                }
            }.padding(32).frame(maxWidth: 1080)
                .frame(maxWidth: .infinity)
        }.background(Color(nsColor: .windowBackgroundColor))
    }
}

struct Metric: View {
    let value: String
    let label: String
    let icon: String
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).foregroundStyle(.secondary)
                Text(value).font(.largeTitle.weight(.semibold)).monospacedDigit()
                Text(label).font(.caption).foregroundStyle(.secondary)
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
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.title).font(.headline)
                            Text("Скоро").font(.caption).foregroundStyle(.secondary)
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
                PageHeader(eyebrow: "Каталог", title: "Один язык. Настоящее понимание.", subtitle: "Начните с C++. Другие направления пока недоступны и не содержат вымышленных уроков.")
                Card {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("C++", systemImage: "curlybraces").font(.largeTitle.bold())
                        Text(model.course?.summary ?? "")
                        Button("Изучить программу", systemImage: "list.bullet") { model.page = .syllabus }.buttonStyle(.borderedProminent)
                    }
                }
                FutureCourses(entries: model.catalog?.entries.filter { $0.availability == .comingSoon } ?? [])
            }.padding(32).frame(maxWidth: 1040).frame(maxWidth: .infinity)
        }
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
                    HStack(spacing: 16) {
                        Metric(value: "\(finished.filter { model.state(for: $0.id).completion == .automatic }.count)", label: "проверено автоматически", icon: "checkmark.seal")
                        Metric(value: "\(finished.filter { model.state(for: $0.id).completion == .selfReviewed }.count)", label: "отмечено вами", icon: "person.crop.circle.badge.checkmark")
                        Metric(value: "\(course.exercises.count - finished.count)", label: "впереди", icon: "arrow.forward.circle")
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Продолжить с последнего места").font(.headline)
                            Text(model.lesson?.title ?? "Первый урок")
                            if let date = model.document.lastStudyDate {
                                Text("Последнее занятие: \(date.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary)
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
