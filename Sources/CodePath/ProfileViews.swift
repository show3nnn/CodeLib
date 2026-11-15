import AppKit
import LearningCore
import SwiftUI
import UniformTypeIdentifiers

extension LocalProfile.Avatar {
    var localizedTitle: LocalizedStringResource {
        let result: LocalizedStringResource = switch self {
        case .initial: "Инициал имени"
        case .leaf: "Лист"
        case .mountain: "Горы"
        case .star: "Звезда"
        case .photo: "Фотография"
        }
        return PresentationLocale.resource(result)
    }
}

struct ProfileAvatar: View {
    let profile: LocalProfile
    var size: CGFloat = 52
    var body: some View {
        Group {
            if profile.avatar == .photo, let data = profile.photo, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else if profile.avatar == .initial {
                Text(profile.initial.isEmpty ? "?" : profile.initial).font(.system(size: size * 0.4, weight: .semibold))
            } else {
                Image(systemName: profile.avatar.symbol).font(.system(size: size * 0.4))
            }
        }.frame(width: size, height: size).foregroundStyle(.green)
            .background(.green.opacity(0.12)).clipShape(Circle()).accessibilityHidden(true)
    }
}

struct ProfileFields: View {
    @Binding var profile: LocalProfile
    var locale: Locale = PresentationLocale.locale
    @State private var selectedImage: NSImage?
    @State private var imageError: AppFailure?
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 18) {
                ProfileAvatar(profile: profile, size: 80)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("НИКНЕЙМ").font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(profile.nickname.count)/30").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    TextField("Как к вам обращаться?", text: $profile.nickname)
                        .textFieldStyle(.roundedBorder).controlSize(.large).accessibilityIdentifier("profile-nickname")
                    Text("Имя только на вашем Mac. От 1 до 30 символов.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Аватар").font(.headline)
            HStack(spacing: 10) {
                ForEach(LocalProfile.Avatar.allCases.filter { $0 != .photo }, id: \.self) { avatar in
                    Button {
                        profile.avatar = avatar
                        profile.photo = nil
                    } label: {
                        Image(systemName: avatar.symbol).font(.system(size: 21, weight: .medium))
                            .frame(width: 52, height: 52)
                            .foregroundStyle(profile.avatar == avatar ? Color.green : .secondary)
                            .background(profile.avatar == avatar ? Color.green.opacity(0.1) : Color.primary.opacity(0.04),
                                        in: RoundedRectangle(cornerRadius: 15))
                            .contentShape(RoundedRectangle(cornerRadius: 15))
                    }
                    .buttonStyle(.plain)
                    .help(Text(PresentationLocale.resource(avatar.localizedTitle, locale: locale)))
                    .accessibilityLabel(Text(PresentationLocale.resource(avatar.localizedTitle, locale: locale)))
                    .accessibilityAddTraits(profile.avatar == avatar ? .isSelected : [])
                    .overlay { if profile.avatar == avatar { RoundedRectangle(cornerRadius: 15).strokeBorder(.green, lineWidth: 1.5) } }
                }
                Spacer(minLength: 0)
            }
            HStack {
                Button("Загрузить фото…", systemImage: "photo.badge.plus") { choosePhoto() }
                    .buttonStyle(.bordered).controlSize(.large)
                if profile.avatar == .photo {
                    Button("Убрать фото") { profile.photo = nil; profile.avatar = .initial }.buttonStyle(.borderless)
                }
            }
            if let imageError { FailureText(failure: imageError, fallback: "Не удалось подготовить аватар.", locale: locale).foregroundStyle(.red).font(.caption) }
            Text("Фото хранится вместе с прогрессом и входит в экспорт. Ничего не загружается в сеть.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: Binding(get: { selectedImage != nil }, set: { if !$0 { selectedImage = nil } })) {
            if let image = selectedImage {
                AvatarCropView(image: image, locale: locale) { data in
                    profile.avatar = .photo
                    profile.photo = data
                    selectedImage = nil
                }
            }
        }
    }

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { selectedImage = try AvatarPhoto.load(url); imageError = nil }
        catch { imageError = AppFailure(error) }
    }
}

struct EditProfileView: View {
    let model: AppModel
    @State var profile: LocalProfile
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("ВАШ ПРОФИЛЬ").font(.system(size: 10, weight: .bold)).tracking(1.6).foregroundStyle(.green)
                Text("Сделайте его своим.").font(.system(size: 28, weight: .bold)).tracking(-0.7)
                Text("Имя и аватар появятся на главной и в навигации.").foregroundStyle(.secondary)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Card { ProfileFields(profile: $profile, locale: model.presentationLocale) }
                    if failed {
                        FailureText(failure: model.saveError ?? model.message, fallback: "Не удалось сохранить профиль.", locale: model.presentationLocale)
                            .foregroundStyle(.red).textSelection(.enabled)
                    }
                }.padding(24)
            }
            Divider()
            HStack {
                Button("Отмена") { dismiss() }
                Spacer()
                Button("Сохранить") {
                    profile.nickname = LocalProfile.normalizedName(profile.nickname)
                    if model.saveProfile(profile) { dismiss() } else { failed = true }
                }.buttonStyle(.borderedProminent)
            }.controlSize(.large).padding(20)
        }.frame(width: 600, height: 590).background(WorkspaceBackdrop())
    }
}

struct OnboardingView: View {
    @Bindable var model: AppModel
    @State private var state = OnboardingState()
    @State private var theme = "system"
    @State private var failed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("codelib").font(.headline).foregroundStyle(.green)
                switch state.step {
                case .welcome:
                    Text("Добро пожаловать в codelib").font(.largeTitle.bold())
                    WelcomeCodeView()
                    Text("Учимся программировать на C++ — офлайн и в своём темпе. Код можно запустить в изолированной среде; AI нет.")
                        .foregroundStyle(.secondary)
                    Button("Начать настройку") { advance(to: .profile) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                case .profile:
                    Group {
                        if model.isExistingLearner { Text("Добавим ваш профиль") }
                        else { Text("Познакомимся?") }
                    }.font(.largeTitle.bold())
                    if model.isExistingLearner { Text("Прежние задания, ответы и черновики останутся на месте.").foregroundStyle(.secondary) }
                    ProfileFields(profile: $state.draft, locale: model.presentationLocale)
                    HStack {
                        Button("Назад") { advance(to: .welcome) }
                        Spacer()
                        Button("Далее") {
                            state.draft.nickname = LocalProfile.normalizedName(state.draft.nickname)
                            advance(to: .appearance)
                        }.buttonStyle(.borderedProminent)
                    }
                case .appearance:
                    Text("Комфортное оформление").font(.largeTitle.bold())
                    Picker("Тема", selection: $theme) {
                        Text("Как в macOS").tag("system")
                        Text("Светлая").tag("light")
                        Text("Тёмная").tag("dark")
                    }.pickerStyle(.segmented)
                    HStack(spacing: 16) {
                        themePreview("Светлая", dark: false)
                        themePreview("Тёмная", dark: true)
                    }
                    Text("Сейчас доступны русский интерфейс и курс C++. English появится после полного перевода, без смешения языков.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("Назад") { advance(to: .profile) }
                        Spacer()
                        Button("Далее") { advance(to: .environment) }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    }
                case .environment:
                    Text("Подготовим ваш Mac к программированию").font(.largeTitle.bold())
                    ExecutionReadinessView(execution: model.execution)
                    HStack {
                        Button("Назад") {
                            if model.execution.readiness == .checking { model.execution.cancel() }
                            advance(to: .appearance)
                        }
                        Spacer()
                        Button("Начать обучение") {
                            if model.execution.readiness == .checking { model.execution.cancel() }
                            failed = !model.saveOnboarding(state, theme: theme, finish: true)
                        }.buttonStyle(.borderedProminent).controlSize(.large)
                    }
                }
                if failed {
                    FailureText(failure: model.saveError ?? model.message, fallback: "Не удалось сохранить настройку. Повторите действие.", locale: model.presentationLocale)
                        .foregroundStyle(.red).textSelection(.enabled)
                }
                Text("Настройка хранится только на этом Mac").font(.caption).foregroundStyle(.secondary)
            }.padding(40).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }
        .preferredColorScheme(theme == "dark" ? .dark : theme == "light" ? .light : nil)
        .onAppear {
            state = model.document.onboarding ?? OnboardingState()
            if model.document.onboarding == nil && model.isExistingLearner { state.step = .profile }
            theme = model.document.preferences.theme
        }
    }

    private func advance(to step: OnboardingState.Step) {
        var next = state
        next.step = step
        if model.saveOnboarding(next, theme: theme) {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { state = next }
            failed = false
        } else { failed = true }
    }

    private func themePreview(_ title: LocalizedStringResource, dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(PresentationLocale.resource(title, locale: model.presentationLocale)).font(.headline)
            Text("C++ · первый шаг").font(.caption)
            Text("std::cout << 42;").font(.system(.body, design: .monospaced)).foregroundStyle(dark ? .mint : .green)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(dark ? .white : .black).background(dark ? Color(white: 0.12) : .white, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(.gray.opacity(0.4)) }
    }
}
