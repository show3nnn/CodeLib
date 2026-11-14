# C++: граница исполнения и состояние прототипа

## Фактически проверено · 14.11.2026

- Установлены полный Xcode и Apple clang **21.0.0**, target **arm64-apple-darwin27.3.0**. Проект использует `/Applications/Xcode.app` через локальный DEVELOPER_DIR.
- C++17 и C++20 реально поддерживаются: разработческая проверка компилирует все 300 примеров/эталонов в обоих режимах, запускает контрольные входы с UBSan внутри `.build/content-check`.
- Xcode-конфигурации приложения содержат **ENABLE_APP_SANDBOX=NO**; ad-hoc packaged app не имеет sandbox entitlement. Hardened Runtime и codesign verification сами по себе не запрещают доступ к файлам пользователя.
- `kern.hv_support=1`; `VZVirtualMachine.isSupported` и `configuration.validate()` проходят. Swift-helper с ad-hoc подписью и единственным entitlement `com.apple.security.virtualization` реально запускает Linux на этом Mac.
- Небольшой доверенный native fixture отдельно подтвердил C++17 (`201703`) и C++20 (`202002`). Это не выполнение пользовательского исходника на хосте.

## Выбранное решение этапа 3

Developer-only прототип `scripts/execution_probe/Helper.swift` использует поддерживаемый **Virtualization.framework**, а не `sandbox-exec`, `sandbox_init` или обычный Process как «песочницу». Каждому запросу соответствует новая VM:

- **Компиляция и исполнение происходят только в госте** (Alpine ARM64, GCC 14.2 / musl, C++17/20). Apple clang остаётся компилятором приложения/разработческих проверок, а не незащищённым обработчиком пользовательского `#include`.
- В конфигурации VM нет сетевых устройств, дисков, directory shares, vsock или проброшенных устройств хоста. Файлы задания существуют только в гостевом RAM-rootfs; обновление прогресса не входит в протокол.
- Единственный канал — virtio serial. Host принимает ограниченный JSON (`source`, `stdin`, стандарт строго `17`/`20`), передаёт исходник/ввод как base64, принимает ограниченный структурированный результат. Нет shell-команд на хосте, интерполяции исходника в shell, произвольных путей/флагов компилятора из запроса.
- Доверенный `/init` работает как guest PID 1. Компилятор и программа запускаются как UID 65534 с hard rlimits. Они не получают дескриптор serial-консоли и не могут подделать framing через обычный stdout. `ulimit`-ошибка прекращает запуск.
- 1 vCPU, **1 GiB гостевой физической памяти** без balloon/swap/дисков. Это граница guest RAM, **не обещание суммарного RSS хостового VM-сервиса ровно 1 GiB**: у Virtualization есть накладные расходы.
- Компилятор: CPU 8 с, address space 384 MiB, файл 8 MiB, FD 64, NPROC 32. Программа: CPU soft/hard 1/2 с, address space 128 MiB, файл 64 KiB, FD/NPROC 32. NPROC — лимит UID внутри VM, не всей macOS. Даже обход ограничения внутри скомпрометированного гостя не выводит потомков за границу VM.
- На host: исходник/stdin по 64 KiB, каждый output stream до 64 KiB, общий serial transport 256 KiB, wall time всей VM 30 с. SIGTERM/SIGINT означает отмену. Завершение — принудительный `VM.stop()`, а не просьба гостю завершиться. Последний watchdog завершает helper на 35 с без ложного success, если framework зависнет.
- После остановки отбрасывается вся VM вместе с потомками и гостевыми файлами. Нет постоянного writable-диска задания; kernel/initrd — переиспользуемые developer-артефакты, не пользовательские данные.

### Воспроизведение

```sh
bash scripts/execution-probe.sh --quick   # real compile → run → Hello, VM!
bash scripts/execution-probe.sh           # позитивные, отрицательные и lifecycle-проверки
```

Требуются Apple silicon, Xcode и доступность Virtualization. Первый запуск скачивает **119 586 613 байт (~114 MiB)** с официального Alpine CDN, только в `.build/execution-probe/downloads`. Список из 19 точных артефактов/размеров/SHA256 закреплён в `image-lock.json`; обновления отпечатков нет. Rootfs SHA256 сверен с официальным Alpine release manifest. APK-подписи toolchain и kernel проверяются ключами из pinned rootfs внутри гостя, без `--allow-untrusted` и без сети. Доверие к первоначальному rootfs/lock основано на HTTPS официального зеркала; это не независимый аудит цепочки поставки.

`image.py` не распаковывает чужие symlinks/tar на host: формирует deterministic newc initrd из данных, отклоняет traversal и удаляет suid/sgid. Linux-бинарники не исполняются на macOS. GCC/kernel/rootfs не добавляются в Git, app resources, Package.swift или Xcode-проект. Системные установки, глобальный xcode-select и пользовательские настройки не меняются.

### Что остаётся перед подключением к приложению (этап 4)

**Приложение 0.2.0 пока не компилирует и не исполняет C++.** Этот отдельный CLI-прототип — не shipped compiler и не завершение §16–19:

1. Перенести проверенный механизм в продуктовый helper/адаптер: доверенные assets и проверка их целостности непосредственно перед запуском, упаковка/signing, единая очередь **не более одной VM** на приложение, ограниченный IPC и отмена при закрытии/падении app. Сейчас драйвер запускает тесты последовательно; произвольный запуск нескольких CLI-helper не ограничен общим scheduler.
2. Уменьшить/подготовить guest image заранее (сейчас APK устанавливаются в RAM при каждом старте), проверить стоимость boot/RAM на целевых Mac и распространение ~114 MiB dependencies с лицензиями. Пока это developer-only, не установщик и не скрытая загрузка при старте приложения.
3. Уточнить product results: сейчас сохраняются диагностика/exit code; SIGKILL возвращается как runtimeError, без выдуманного определения OOM/CPU. Для точного различения причин нужен guest supervisor с `wait4`/cgroup accounting. Wrong answer и проверка fixtures — последующий grader, а не успех завершения процесса.
4. Добавить UI консоли/Run/Stop, позиционные диагностики, compiler readiness/onboarding, корректное обновление прогресса/наград **только после** настоящей проверки. Не менять смысл прежней `.automatic` проверки однозначных ответов молча.
5. Повторить негативные проверки **у упакованного helper и приложения**, включая malformed/truncated IPC, отказ/отсутствие/подмену assets, старт/отмену/аварийное завершение, общий предел concurrency. Прототип и hand-authored probes не являются независимым security audit или доказательством отсутствия гипервизорных уязвимостей.

### Официальные основания выбора

- [Apple: Running Linux in a virtual machine](https://developer.apple.com/documentation/virtualization/running-linux-in-a-virtual-machine) — Linux kernel/initrd, native CLI helper, serial transport.
- [VZVirtualMachineConfiguration.memorySize](https://developer.apple.com/documentation/virtualization/vzvirtualmachineconfiguration/memorysize) — fixed guest physical memory и host overhead.
- [VZVirtualMachine.stop](https://developer.apple.com/documentation/virtualization/vzvirtualmachine/stop(completionhandler:)) — принудительная остановка без согласия гостя.
- [Virtualization entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.virtualization).
- Локальный `man getrlimit`: macOS RLIMIT_RSS влияет на предпочтение вытеснения страниц при нехватке памяти, а не создаёт достаточный hard memory cap. App Sandbox не подменяет управление всеми ресурсами/деревом процессов.
