# C++: граница исполнения · 0.3.0

## Фактически проверено · 14.11.2026

- Установлены полный Xcode и Apple clang **21.0.0**, target **arm64-apple-darwin27.3.0**. Проект использует `/Applications/Xcode.app` через локальный DEVELOPER_DIR.
- C++17 и C++20 реально поддерживаются: разработческая проверка компилирует все 300 примеров/эталонов в обоих режимах, запускает контрольные входы с UBSan внутри `.build/content-check`.
- Xcode-конфигурации приложения содержат **ENABLE_APP_SANDBOX=NO**; ad-hoc packaged app не имеет sandbox entitlement. Hardened Runtime и codesign verification сами по себе не запрещают доступ к файлам пользователя.
- `kern.hv_support=1`; `VZVirtualMachine.isSupported` и `configuration.validate()` проходят. Swift-helper с ad-hoc подписью и единственным entitlement `com.apple.security.virtualization` реально запускает Linux на этом Mac.
- Небольшой доверенный native fixture отдельно подтвердил C++17 (`201703`) и C++20 (`202002`). Это не выполнение пользовательского исходника на хосте.

## Реализация этапов 3–4

Прототип этапа 3 перенесён в `Sources/ExecutionHelper/Helper.swift`; `Sources/ExecutionSupport/` содержит протокол, проверку образов/подписей и ограниченный host-adapter. Приложение запускает только подписанный `Contents/Helpers/CodelibExecutionHelper`. Поддерживаемый **Virtualization.framework**, а не `sandbox-exec`, `sandbox_init` или обычный Process, создаёт границу изоляции. Каждому запросу соответствует новая VM:

- **Компиляция и исполнение происходят только в госте** (Alpine ARM64, GCC 14.2 / musl, C++17/20). Apple clang остаётся компилятором приложения/разработческих проверок, а не незащищённым обработчиком пользовательского `#include`.
- В конфигурации VM нет сетевых устройств, дисков, directory shares, vsock или проброшенных устройств хоста. Файлы задания существуют только в гостевом RAM-rootfs; обновление прогресса не входит в протокол.
- Единственный guest-канал — virtio serial. Host-helper принимает ограниченный JSON (`version=1`, UUID задания, `source`, `stdin`, стандарт строго `17`/`20`), передаёт исходник/ввод как base64, возвращает NDJSON с реальными фазами boot/compile/run и результатом. Host-adapter проверяет UUID, порядок фаз, единственность результата, exit status, размеры и EOF; повреждённый протокол не считается успехом. Нет shell-команд на хосте, интерполяции исходника в shell, произвольных путей/флагов компилятора из запроса.
- Доверенный `/init` работает как guest PID 1. Гостевой C-supervisor до `exec` сбрасывает группы/UID до65534 и устанавливает hard rlimits; close-on-exec error pipe подтверждает успешную настройку/exec. Root-parent получает настоящий `wait4` status, а не угадывает сигнал по shell exit-code. Компилятор/программа не получают serial-консоль или статусный дескриптор и не могут подделать framing через stdout. Ошибка настройки блокирует запуск.
- 1 vCPU, **1 GiB гостевой физической памяти** без balloon/swap/дисков. Это граница guest RAM, **не обещание суммарного RSS хостового VM-сервиса ровно 1 GiB**: у Virtualization есть накладные расходы.
- Компилятор: CPU8 с, address space384 MiB, файл8 MiB, FD64, NPROC32. Программа: CPU soft/hard1/2 с, address space128 MiB, файл65537 байт (один sentinel byte для точного определения переполнения64KiB), FD/NPROC32. Ровно64KiB вывода допустимы; наружу передаётся максимум64KiB. NPROC — лимит UID внутри VM, не всей macOS. Даже обход ограничения внутри скомпрометированного гостя не выводит потомков за границу VM.
- На host: исходник/stdin по 64 KiB, каждый output stream до 64 KiB исходных байт (invalid UTF-8 заменяется для отображения), serial transport 256 KiB, helper→app transport 1 MiB, wall time VM30 с. Helper watchdog35 с; app-adapter deadline40 с и SIGKILL через2 с после отмены/отказа, если штатная остановка не отвечает. SIGTERM/SIGINT означает отмену. `VM.stop()` принудителен, не требует согласия гостя.
- `CodeExecutionController` держит единственный слот на всё приложение: повторный запуск отвергается до reap прежнего helper. Переход со страницы/смена задания/импорт/сброс/закрытие настоящего hosting window отменяют задачу. Helper следит за своим родителем; crash app или SIGKILL helper уничтожает VM. Это не общий лимит для нескольких независимых экземпляров приложения/CLI.
- После остановки отбрасывается VM вместе с потомками и файлами. Нет постоянного writable-диска задания; kernel/initrd — read-only по политике assets, включённые в bundle. Контрольные SHA256/точные размеры закреплены **в исполняемом коде**, а не в заменяемом manifest рядом с образами; symlinks и non-regular files отвергаются.
- Перед каждым запуском app проверяет подпись своего bundle с nested code, подпись/identifier/единственный virtualization entitlement helper и хеши образов. Helper повторяет проверку образов. Он подписан с Hardened Runtime; host-adapter не наследует DYLD/прочее окружение app. Это защита от повреждения/подмены assets, не от владельца macOS, который может модифицировать и переподписать всё приложение.

### Воспроизведение

```sh
bash scripts/execution-probe.sh --quick   # real compile → run → Hello, VM!
bash scripts/execution-probe.sh           # позитивные, отрицательные и lifecycle-проверки
bash scripts/build.sh                     # guest/helper входят в dist/codelib.app
PYTHONDONTWRITEBYTECODE=1 python3 scripts/execution_probe/test.py --app dist/codelib.app
bash scripts/ui-smoke.sh --execution-only # реальные app controller, окно и NSTextView
```

Для **сборки** нужны Apple silicon, Xcode и доступность Virtualization. Первая сборка скачивает **119 586 613 байт (~114 MiB)** с официального Alpine CDN, только в `.build/execution-probe/downloads`. Список из 19 точных артефактов/размеров/SHA256 закреплён в `image-lock.json`; обновления отпечатков нет. Rootfs SHA256 сверен с официальным Alpine release manifest. APK-подписи toolchain и kernel проверяются ключами из pinned rootfs внутри гостя, без `--allow-untrusted` и без сети. Доверие к первоначальному rootfs/lock основано на HTTPS официального зеркала; это не независимый аудит цепочки поставки.

`image.py` не распаковывает чужие symlinks/tar на host: формирует deterministic newc initrd из данных, отклоняет traversal и удаляет suid/sgid. Выходные файлы записываются атомарно. Linux-бинарники не исполняются на macOS. Обе сборки (SwiftPM/Xcode) используют `package_execution.sh`: guest resources (~147 MiB) входят в `.app`, **не в Git**. В готовом app не нужны сеть, CLT или Xcode. Системные установки, глобальный xcode-select и пользовательские настройки не меняются.

### Проверки этапа 4 и границы готовности

**45/45 integration checks** упакованного helper прошли: compile/run/limits probes, обычные exit152/153 вместо сигнала, ровно64KiB output, malformed/oversized/version IPC, отсутствие/изменение образов/symlink, SIGKILL helper с завершением Apple VM-worker и смерть родителя. **25/25 app smoke**: реальный controller/один слот, stdin→stdout, диагностика/навигация NSTextView без undo-правок, Stop/navigation/window close и неизменность progress.json. Отдельный Swift-тест проверяет неподписанный helper/неверный app bundle. Это не независимый security audit и не доказательство отсутствия гипервизорных уязвимостей.

Осталось:

1. **Этап 5:** runtime grader/fixtures/≥5 сценариев для подходящих задач. Сейчас Run не меняет completion/awards/studyDays и не пишет прогресс. UI явно предупреждает, что success означает только exit0 и относится к снимку исходника/ввода. Файловые fixtures не передаются. Не менять смысл старой `.automatic` проверки молча.
2. **Этап 6:** readiness/onboarding. При missing/modified assets или неверной подписи запуск уже блокируется с сообщением; предварительного onboarding-экрана проверки среды нет.
3. Реальный SIGXCPU из wait4 возвращается как cpuLimit; обычные exit152/exit153 остаются runtimeError. SIGKILL — runtimeError с кодом137, без выдуманного определения OOM/CPU: для точного определения источника SIGKILL нужен дополнительный accounting. APK и доверенный supervisor пока подготавливаются в RAM при каждом boot; уменьшение образа и независимые performance/RAM measurements остаются оптимизациями.
4. Personal ad-hoc build — не распространение/notarization. Перед передачей бинарных образов другим людям обеспечить точные corresponding sources/лицензии GPL/LGPL и notices: `packaging/ExecutionThirdParty.txt`. Здесь third-party binaries не публикуются в Git.

### Официальные основания выбора

- [Apple: Running Linux in a virtual machine](https://developer.apple.com/documentation/virtualization/running-linux-in-a-virtual-machine) — Linux kernel/initrd, native CLI helper, serial transport.
- [VZVirtualMachineConfiguration.memorySize](https://developer.apple.com/documentation/virtualization/vzvirtualmachineconfiguration/memorysize) — fixed guest physical memory и host overhead.
- [VZVirtualMachine.stop](https://developer.apple.com/documentation/virtualization/vzvirtualmachine/stop(completionhandler:)) — принудительная остановка без согласия гостя.
- [Virtualization entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.virtualization).
- Локальный `man getrlimit`: macOS RLIMIT_RSS влияет на предпочтение вытеснения страниц при нехватке памяти, а не создаёт достаточный hard memory cap. App Sandbox не подменяет управление всеми ресурсами/деревом процессов.
