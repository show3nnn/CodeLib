#!/usr/bin/env python3
"""Compiler-derived developer String Catalog. No partial English is copied into the app."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import platform
import re
import ui_en


def source_files(root):
    return {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted((root / "Sources/CodePath").rglob("*.swift"))}


def placeholders(text):
    return Counter(re.findall(r"%(?:\d+\$)?[-+#0 ']*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|ll|h|l|j|z|t|L)?[@diouxXfFeEgGaAcCsSpn%]", text))


def catalog(manifest, translations):
    entries = manifest["entries"]
    if set(translations) - set(entries):
        raise ValueError("Переводы UI содержат ключи, не извлечённые компилятором")
    strings = {}
    for key, locations in entries.items():
        item = dict(extractionState="manual", comment="; ".join(locations),
                    localizations={"ru": {"stringUnit": {"state": "translated", "value": key}}})
        if key in translations:
            translated = translations[key]
            if not translated.strip() or placeholders(key) != placeholders(translated):
                raise ValueError(f"Пустой перевод или несовпадение placeholders: {key}")
            item["localizations"]["en"] = {"stringUnit": {"state": "translated", "value": translated}}
        strings[key] = item
    return dict(sourceLanguage="ru", version="1.0", strings=strings)


def encoded(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def extract(root):
    folder = root / f".build/xcode/Build/Intermediates.noindex/CodePath.build/Release/CodePath.build/Objects-normal/{platform.machine()}"
    sources = source_files(root)
    entries = {}
    for relative in sources:
        source = root / relative
        path = folder / (source.stem + ".stringsdata")
        if not path.exists():
            raise ValueError("Сначала запустите extract_ui_localization.sh для свежих данных Xcode")
        data = json.loads(path.read_text())
        if Path(data["source"]).resolve() != source.resolve():
            raise ValueError(f"Неоднозначный источник извлечённых строк: {relative}")
        for table, values in data.get("tables", {}).items():
            if table != "Localizable": raise ValueError(f"Неизвестная таблица: {table}")
            for value in values:
                key = value["key"]
                if not key: continue
                line = value["location"]["startingLine"]
                entries.setdefault(key, set()).add(f"{relative}:{line}")
    return dict(formatVersion=1, sourceFiles=sources, entries={key: sorted(values) for key, values in entries.items()})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--extract", action="store_true", help="Прочитать свежие .stringsdata Xcode и обновить manifest")
    parser.add_argument("--check", action="store_true", help="Проверить исходники и каталог без Xcode и перезаписи")
    args = parser.parse_args()
    if args.extract and args.check: parser.error("--extract и --check несовместимы")
    root = Path(__file__).resolve().parents[1]
    folder = root / "localization/ui"
    manifest_path = folder / "extraction.json"
    if args.extract:
        manifest = extract(root)
        folder.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(encoded(manifest))
    else:
        manifest = json.loads(manifest_path.read_text())
    if manifest["formatVersion"] != 1 or manifest["sourceFiles"] != source_files(root):
        raise SystemExit("UI-исходники изменились; пересмотрите строки и запустите extract_ui_localization.sh")
    document = catalog(manifest, ui_en.TEXTS)
    path = folder / "Localizable.xcstrings"
    text = encoded(document)
    if args.check:
        if not path.exists() or path.read_text() != text:
            raise SystemExit("String Catalog отличается от извлечённых ключей/авторского перевода")
    else:
        path.write_text(text)
    print(f"UI-черновик: {len(ui_en.TEXTS)}/{len(document['strings'])} ключей компилятора; НЕ полный UI и НЕ ресурс app.")


if __name__ == "__main__":
    main()
