"""Complete developer-only English drafts for catalog and release history. Not reviewed."""
CATALOG_SHA256 = "bd375a5474c459144861a65ea0c3221711d199e3b403660c3048048be3bead8c"
# Reviewed source change: only the real 0.1.14 note was added and translated below.
RELEASES_SHA256 = "c0f9266af7d90e9ad77857f0224b0c1bdf340f4d38739e5b7597a08a90f9ceab"
FUTURE = "A future course. Learning materials are not available yet."
CATALOG = {
    "cpp-foundations": dict(title="C++ — from zero to a confident first year", summary="Practice, language understanding and console projects."),
    "python-future": dict(title="Python", summary=FUTURE),
    "javascript-future": dict(title="JavaScript", summary=FUTURE),
    "java-future": dict(title="Java", summary=FUTURE),
    "rust-future": dict(title="Rust", summary=FUTURE),
}


def note(title, summary, features, improvements=None, fixes=None):
    return dict(title=title, summary=summary,
                features={key: dict(title=value[0], detail=value[1]) for key, value in features.items()},
                improvements=improvements or {}, fixes=fixes or {})


RELEASES = {
    "0.1.14": note("One language for dates and errors",
        "Continuing CHANGELOG1 §10: the interface uses an explicit Russian locale, and system errors get understandable messages instead of text in an arbitrary macOS language. English is not enabled yet.",
        {
            "presentation-locale": ("The app locale, not the system locale", "The main window, Settings, history and About use one Russian locale. Profile, study and award dates, percentages and dynamic text resources are formatted explicitly; the time zone remains local."),
            "system-errors": ("A reason based on the error code", "Permission failures, missing files, insufficient space, read-only volumes and existing files have separate messages based on Cocoa and POSIX domain/code pairs. Unknown errors use a neutral message without text matching."),
            "diagnostics": ("Diagnostics on demand", "The original error is retained. Technical text with its domain and code is available separately and copied only at the user's request; it may remain in the system language and is never sent anywhere."),
        },
        {
            "Подписи предпросмотра темы и предупреждение при выходе подготовлены как штатные локализуемые ресурсы Apple.": "Theme preview labels and the quit warning are prepared as native Apple localizable resources.",
            "Форматирование не меняет сохранённые даты, ключи учебных дней, прогресс или настройки.": "Formatting does not change persisted dates, study-day keys, progress or preferences.",
        }),
    "0.1.13": note("Catalog and history without losing identity",
        "Continuing CHANGELOG1 §10: text-only English drafts now cover the catalog and the entire release history. The app remains in Russian; the translations are not reviewed and are not bundled.",
        {
            "resource-translation": ("Resource text separate from logic", "Titles, descriptions, feature cards, improvements and fixes are translated. Versions, dates, stages, course and feature IDs, icons and course availability remain canonical."),
            "stable-keys": ("Keys do not depend on position", "The catalog uses course IDs; history uses versions and feature IDs. Improvement and fix strings are addressed by a fingerprint of the source value, not an array index."),
            "validation": ("A complete draft is not a ready language", "Source SHA256, coverage, empty or unknown fields and resource type are checked. Loaders reject drafts; previews do not change update order, routing or the read marker."),
        },
        {
            "Авторские переводы и генератор воспроизводимы, черновики остаются вне Resources.": "Authored translations and generation are reproducible; drafts stay outside Resources.",
            "Изменение release notes требует осмысленного пересмотра перевода, а не автоматической подмены fingerprint.": "Changes to release notes require a deliberate translation review, not automatic fingerprint replacement.",
        }),
    "0.1.12": note("Errors with a clear cause",
        "Continuing CHANGELOG1 §10: core error reasons are separate from text, and the UI retains the original error, formatting it with native Apple resources when displayed. Full English is not enabled yet.",
        {
            "typed-errors": ("A reason instead of a string", "Course, translation, profile, catalog, history and storage errors have typed reasons and parameters. Core Russian fallbacks are preserved; LearningCore remains independent of SwiftUI."),
            "error-ui": ("A template and its underlying error", "Export, import, reset, recovery and photo handling use structured messages. The underlying reason uses the same explicit locale; unknown system diagnostics remain data rather than being translated through text matching."),
            "storage": ("Progress protections remain intact", "Tests cover failure types, revision conflicts, locks, protected exports and file preservation on failed import or reset. A message is not a substitute for a successful write."),
        },
        {
            "Проверки полноты курса по-прежнему не превращают draft в reviewed.": "Course coverage checks still do not turn a draft into a reviewed translation.",
            "Фото и ошибки декодирования получают явные UI-шаблоны вместо готовых строк в состоянии.": "Photo and decoding errors use explicit UI templates instead of preformatted strings in state.",
        }),
    "0.1.11": note("A translation draft of the entire course",
        "All 2904 text fields of the English draft are prepared: 17 sections, 64 lessons and 296 tasks. This is a technically complete draft, not an English app ready for use: review, errors, resources and language selection still need work.",
        {
            "course-english": ("Projects, review and the algorithm lab", "The last 10 lessons and 48 tasks cover console protocols, file preservation, the final dispatcher, prefixes, windows, two pointers and binary search on the answer. Code, canonical answers and fixtures are unchanged."),
            "review-gate": ("Coverage does not replace review", "Tests confirm 2904/2904 coverage and draft status: the production loader rejects an unreviewed translation even when complete. File-based checks cover all 97 automatically checked course answers."),
            "ui-resources": ("Menus, statuses and avatars as resources", "Page names, task types, completion statuses and avatars are prepared for native Apple localization in the UI layer. Persisted enum values and progress are unchanged."),
        },
        {
            "Переводимые подписи не используются как ключи прогресса.": "Translated labels are not used as progress keys.",
            "Статус draft не меняется автоматически при достижении полного покрытия; English пока не предлагается.": "Draft status does not change automatically at full coverage; English is not offered yet.",
        }),
    "0.1.10": note("Objects, guarantees and reliable data",
        "Continuing CHANGELOG1 §10: the developer translation covers 14 sections, 54 lessons and 248 tasks. Category labels and achievement messages are prepared for native Apple localization. English remains unavailable until translation is complete.",
        {
            "course-english": ("Another 11 lessons and 44 tasks", "Structures and classes, constructors and invariants, const/constexpr and C++ guarantees, map/set, files and errors. The English draft now contains 2437 of 2904 text fields without changing C++, answers or fixtures."),
            "achievement-strings": ("Achievements without concatenated translations", "Categories use LocalizedStringResource in the UI layer. Hidden labels, recognition and acquisition dates, and banners use explicit localizable templates. All 24 achievement titles still appear in Russian, like the rest of the app."),
            "progress": ("Keeping canonical answers", "A file-based round trip covers 31 choice tasks from sections 6–14 and preserves drafts, profile, awards, positions and unknown IDs. Translation does not create separate progress."),
        },
        {
            "LearningCore остаётся независимым от SwiftUI; ресурсы категорий объявлены в UI.": "LearningCore remains independent of SwiftUI; category resources are declared in the UI.",
            "Секретные награды по-прежнему не раскрывают название и условие до получения.": "Secret achievements still hide their titles and requirements until earned.",
        }),
    "0.1.9": note("Ranges, memory and interface language",
        "Continuing CHANGELOG1 §10: the developer translation covers 11 sections, 43 lessons and 204 tasks. Headers and metrics use native Apple localizable resources. Full English is not ready or enabled yet.",
        {
            "course-english": ("Algorithms, pointers and RAII", "Another 11 lessons and 44 tasks are translated: begin/end ranges, search and sorting, lifetime, ownership and invalidation. The draft contains 1994 of 2904 text fields without changing C++, answers or progress."),
            "native-strings": ("Dynamic labels become resources", "PageHeader and Metric labels use LocalizedStringResource instead of plain String. Xcode extracted 23 additional keys, including the greeting with a name. The developer-only catalog covers 209/209 keys, not all app messages."),
            "compatibility": ("Canonical answers stay the same", "The file round trip now covers 21 choice tasks from sections 6–11. Profile, drafts, positions, awards and unknown IDs are checked; changing the course presentation does not modify the progress file."),
        },
        {
            "Регистр заголовка оформляется после локализации, не преобразованием исходного ключа.": "Header case is applied after localization, not by transforming the source key.",
            "Имя пользователя остаётся буквальным параметром приветствия, а fallback первого урока извлекается отдельно.": "The user's name remains a literal greeting parameter, and the first-lesson fallback is extracted separately.",
        }),
    "0.1.8": note("Functions, text and collections",
        "Continuing full translation under CHANGELOG1 §10. Developer English covers eight sections and all 186 previously extracted UI keys. This is not yet a complete English course or interface; the app remains in Russian.",
        {
            "course-english": ("Another 12 lessons and 60 tasks", "Functions and contracts, ASCII and UTF-8, significant spaces, searching, and array and vector bounds. The draft contains 1554 of 2904 text fields, 32 lessons and 160 tasks."),
            "ui-catalog": ("Extracted keys translated", "The developer catalog covers 186/186 compiler-extracted keys for lessons, syllabus, statistics, achievements and history. Dynamic messages and resource data still need localization; the catalog is not bundled."),
            "progress": ("Checking translation preserves data", "A file-based test for the new sections preserves canonical answers, drafts, lesson positions, profile and awards when changing course presentation. This tests the core, not a finished UI language switch."),
        },
        {
            "Защищённые C++, ID, ожидаемые результаты и fixtures не изменены.": "Protected C++, IDs, expected results and fixtures are unchanged.",
            "Неполный English остаётся вне приложения до готовности всех экранов и курса.": "Incomplete English stays outside the app until every screen and the course are ready.",
        }),
    "0.1.7": note("Translation without losing meaning",
        "Continuing CHANGELOG1 §10: the developer translation covers five sections, 20 lessons and 100 tasks. The working interface and course remain in Russian until full English is ready.",
        {
            "course-english": ("Expressions, branching and loops", "Three more complete sections cover grouping, division and bounds, logic, rule priority, loops and streaming telemetry. The draft covers 967 of 2904 text fields."),
            "ui-catalog": ("A native foundation for interface translation", "Xcode compiler extraction and a genuine Apple String Catalog: 76 translations of 186 extracted keys. The catalog is developer-only and is not copied into the app."),
            "contracts": ("Preserving contracts", "IDs, C++, persisted answers and fixtures do not change. Checks cover UI placeholders, declared-section completeness and extraction freshness against current sources."),
        },
        {
            "Каталог UI проходит настоящий компилятор xcstringstool; абсолютные пути разработчика не сохраняются в репозитории.": "The UI catalog passes the real xcstringstool compiler; developer absolute paths are not stored in the repository.",
            "Неполный English не выдаётся за готовый язык и не смешивается с русским UI.": "Incomplete English is not presented as a ready language or mixed into the Russian UI.",
        }),
    "0.1.6": note("A greeting and the first translations",
        "The CHANGELOG1 greeting is refined and the developer translation now covers the first two sections, 8 lessons and 40 tasks. Full English is not ready and is not enabled in the app.",
        {
            "welcome": ("Hello, World! Without unnecessary motion", "Highlighted statements in five languages, a soft fade, skip, and a finite animation with no endless loop. These are output examples, not code execution."),
            "accessibility": ("A calmer introduction", "Reduce Motion shows a statement immediately; Reduce Transparency replaces glass with an opaque panel. After skipping or with reduced motion, all five statements remain manually accessible."),
            "translation": ("Translating whole sections", "All 380 text fields from the first two sections are prepared outside the app. Generation rejects holes within declared sections, duplicate IDs and changes to protected data."),
        },
        {
            "Логика анимации отделена от SwiftUI и проверяется без таймеров; подсветка не переписывает фрагменты кода.": "Animation logic is separate from SwiftUI and tested without timers; highlighting does not rewrite code fragments.",
            "Канонические ID, ответы, C++-исходники и прогресс курса не изменены.": "Canonical IDs, answers, C++ sources and course progress are unchanged.",
        },
        {"Пути доступности проверяются без попыток изменить read-only настройки macOS.": "Accessibility paths are tested without trying to modify read-only macOS settings."}),
    "0.1.5": note("Practice with personality",
        "24 achievements for real actions, an original sound and an award collection. Existing progress is recognized quietly, without a notification flood. This stage adds no lessons: the course contains 17 sections, 64 lessons and 296 tasks.",
        {
            "awards": ("Your collection", "Categories, visible progress, dates, a secret achievement and detail cards. Self-review marks are clearly separate from automatic answers and do not count as running C++."),
            "notifications": ("A small reason to smile", "Sequential glass banners, an original short sound and an on/off preference. Notifications appear only after an award is persisted."),
            "comfort": ("Comfort without losing work", "Preview and separate font-size resets. Resetting a draft to starter code requires confirmation and preserves learning history."),
        },
        {
            "Аватар и недавние награды на главной, счётчик наград в статистике, адаптивные карточки показателей.": "An avatar and recent awards on the home screen, an achievement count in statistics, and adaptive metric cards.",
            "Стабильный UUID профиля и дата создания новых профилей; прежняя неизвестная дата не выдумывается.": "A stable profile UUID and creation date for new profiles; an unknown historical date is not invented.",
        },
        {"Повторные проверки и перезапуски не выдают одну награду снова. Старые и неизвестные ID наград сохраняются.": "Repeated checks and relaunches do not grant an award again. Existing and unknown award IDs are retained."}),
    "0.1.4": note("Algorithms in action",
        "A complete new C++ lab: 1 section, 4 lessons and 24 tasks. There are now 17 sections, 64 lessons and 296 tasks. Your existing progress stays with you.",
        {
            "algorithms": ("From range sums to answer search", "Prefixes and differences, sliding windows, two pointers and binary search. Includes 20 code-writing tasks and a trip-capacity mini-project."),
            "syllabus": ("Find the practice you need", "Search sections, topics, task names and skills; filter lessons by not started, in progress or completed."),
            "resume": ("Continue instead of starting over", "Opening a lesson returns to its saved task or first unfinished task, rather than always its first task."),
        },
        {
            "Новые эталоны проверяются дополнительными независимыми переборными алгоритмами на малых входах.": "New reference solutions receive additional checks against independent brute-force algorithms on small inputs.",
            "Разработческий проверяющий скрипт умеет проверять один раздел, сохраняя общий отчёт.": "The developer verifier can check one section without overwriting the overall report.",
        },
        {"Устранено дублирование проверки подписей вариантов перевода; правила централизованы в валидаторе курса.": "Duplicate translation-choice-label checks are removed; the rules are centralized in course validation."}),
    "0.1.3": note("A foundation for safe translation",
        "A course-localization layer is prepared without changing learning IDs or persisted answers. The interface and available course remain in Russian: full English is not ready yet.",
        {
            "translation": ("Text separate from checking", "Translation changes labels, not C++ sources, expected output, test data or persisted answer-choice values."),
            "validation": ("No mixed languages", "An incomplete, stale or unreviewed translation cannot load as a production course. An English draft of the first lesson is available only to developers."),
            "repository": ("A tidy project", "Checks for published files and conservative cleanup of old diagnostic runs retain the latest reports."),
        },
        {
            "Проверка сохранённого прогресса и ответов при смене отображаемых подписей.": "Persisted progress and answers are checked across changes to displayed labels.",
            "Воспроизводимый генератор перевода с контролем исходной версии курса.": "Reproducible translation generation verifies the source course version.",
        }),
    "0.1.2": note("Meet your lab",
        "A local profile and initial setup without registration. Existing tasks and drafts are preserved. The interface and course are currently in Russian.",
        {
            "profile": ("Your local profile", "A Unicode name, initial, preset avatar or local photo with cropping. Edit the profile in Settings."),
            "welcome": ("A first introduction", "A programming-language greeting with skip and Reduce Motion support. Name and theme setup resumes after closing."),
            "updates": ("Updates at the right moment", "Release history appears after setup, not over it. A new installation starts with learning."),
        },
        {
            "Имя и аватар показаны в боковой панели, приветствие персонализировано.": "Your name and avatar appear in the sidebar, with a personalized greeting.",
            "Настройка завершена только после успешной записи на диск. Ошибку можно исправить и повторить действие.": "Setup completes only after a successful disk write. Errors can be corrected and the action retried.",
        }),
    "0.1.1": note("A new codelib identity",
        "The first stage of the update: a recognizable name, an original icon and a transparent release history. Your existing lessons and results stay with you.",
        {
            "identity": ("Meet codelib", "A new name and an original open-laptop icon. The previous Bundle Identifier and data folder are retained."),
            "version": ("Version without guesswork", "Settings and About codelib show the version, Alpha stage and build number from app metadata."),
            "history": ("History close at hand", "A separate updates window is available from the menu and Settings. The read marker is saved locally."),
        },
        {
            "Зелёный фирменный акцент и общий стиль новых служебных окон.": "A signature green accent and a consistent style for new utility windows.",
            "История обновлений хранится в структурированном offline-ресурсе.": "Release history is stored in a structured offline resource.",
        }),
    "0.1.0": note("The original working CodePath build",
        "The version that existed before rebranding, recorded in Info.plist. No separate release date or stage was recorded; history is not reconstructed through invented releases.",
        {
            "course": ("A hands-on C++ course", "16 sections, 60 lessons and 272 tasks, including assessments and console projects."),
            "editor": ("A native editor", "C++ editing, highlighting, line numbers, drafts and self-completion of code-writing tasks."),
            "storage": ("Local progress", "Atomic writes, backup, export and import. Only unambiguous answers are checked automatically, not source code."),
        }),
}
