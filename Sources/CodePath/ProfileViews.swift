import AppKit
import LearningCore
import SwiftUI
import UniformTypeIdentifiers

extension LocalProfile.Avatar {
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .initial: "Инициал имени"
        case .leaf: "Лист"
        case .mountain: "Горы"
        case .star: "Звезда"
        case .photo: "Фотография"
        }
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
    @State private var selectedImage: NSImage?
    @State private var imageError: AppFailure?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 18) {
                ProfileAvatar(profile: profile, size: 80)
                VStack(alignment: .leading) {
                    TextField("Как к вам обращаться?", text: $profile.nickname)
                        .textFieldStyle(.roundedBorder).accessibilityIdentifier("profile-nickname")
                    Text("1–30 символов, включая Unicode. Это имя только на вашем Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Аватар").font(.headline)
            HStack {
                ForEach(LocalProfile.Avatar.allCases.filter { $0 != .photo }, id: \.self) { avatar in
                    Button {
                        profile.avatar = avatar
                        profile.photo = nil
                    } label: {
                        Image(systemName: avatar.symbol).frame(width: 30, height: 30)
                    }
                    .help(Text(avatar.localizedTitle))
                    .accessibilityLabel(Text(avatar.localizedTitle))
                    .overlay { if profile.avatar == avatar { RoundedRectangle(cornerRadius: 6).stroke(.green, lineWidth: 2) } }
                }
                Button("Загрузить фото…") { choosePhoto() }
            }
            if let imageError { Text(imageError.resource()).foregroundStyle(.red).font(.caption) }
            Text("Один локальный профиль, без регистрации и проверки имени в интернете. Фото хранится внутри локального файла прогресса и его экспорта.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: Binding(get: { selectedImage != nil }, set: { if !$0 { selectedImage = nil } })) {
            if let image = selectedImage {
                AvatarCropView(image: image) { data in
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
        VStack(alignment: .leading, spacing: 22) {
            Text("Локальный профиль").font(.title.bold())
            ProfileFields(profile: $profile)
            if failed { FailureText(failure: model.saveError ?? model.message, fallback: "Не удалось сохранить профиль.").foregroundStyle(.red) }
            HStack {
                Button("Отмена") { dismiss() }
                Spacer()
                Button("Сохранить") {
                    profile.nickname = LocalProfile.normalizedName(profile.nickname)
                    if model.saveProfile(profile) { dismiss() } else { failed = true }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(28).frame(width: 560)
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
                    Text("Учимся программировать на C++ — офлайн и в своём темпе. Код остаётся черновиком: встроенного запуска и AI нет.")
                        .foregroundStyle(.secondary)
                    Button("Начать настройку") { advance(to: .profile) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                case .profile:
                    Text(model.isExistingLearner ? "Добавим ваш профиль" : "Познакомимся?").font(.largeTitle.bold())
                    if model.isExistingLearner { Text("Прежние задания, ответы и черновики останутся на месте.").foregroundStyle(.secondary) }
                    ProfileFields(profile: $state.draft)
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
                        Button("Начать обучение") {
                            failed = !model.saveOnboarding(state, theme: theme, finish: true)
                        }.buttonStyle(.borderedProminent).controlSize(.large)
                    }
                }
                if failed {
                    FailureText(failure: model.saveError ?? model.message, fallback: "Не удалось сохранить настройку. Повторите действие.")
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

    private func themePreview(_ title: String, dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text("C++ · первый шаг").font(.caption)
            Text("std::cout << 42;").font(.system(.body, design: .monospaced)).foregroundStyle(dark ? .mint : .green)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(dark ? .white : .black).background(dark ? Color(white: 0.12) : .white, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(.gray.opacity(0.4)) }
    }
}
