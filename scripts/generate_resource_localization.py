#!/usr/bin/env python3
"""Strict text-only catalog/history drafts. Never auto-promote review status or source fingerprints."""
import argparse
import json
from pathlib import Path
from localization_tools import digest, value_key
import resources_en


def source_texts(source, resource):
    result = {}
    if resource == "catalog":
        for entry in source["entries"]:
            for field in ["title", "summary"]:
                result[f"catalog.{entry['id']}.{field}"] = entry[field]
    elif resource == "releases":
        for note in source["releases"]:
            prefix = f"release.{note['version']}"
            for field in ["title", "summary"]:
                result[f"{prefix}.{field}"] = note[field]
            for feature in note["features"]:
                for field in ["title", "detail"]:
                    result[f"{prefix}.feature.{feature['id']}.{field}"] = feature[field]
            for field, values in [("improvement", note["improvements"]), ("fix", note["fixes"])]:
                for value in values:
                    result[value_key(prefix, field, value)] = value
    else:
        raise ValueError("Неизвестный тип ресурса")
    return result


def build(source_bytes, resource, author, source_sha256):
    if digest(source_bytes) != source_sha256:
        raise ValueError(f"Исходный {resource} изменился: пересмотрите перевод и source SHA256")
    source = json.loads(source_bytes)
    texts = {}
    if resource == "catalog":
        if set(author) != {entry["id"] for entry in source["entries"]}:
            raise ValueError("Неполный/неизвестный ID каталога")
        for entry_id, fields in author.items():
            if set(fields) != {"title", "summary"}: raise ValueError("Защищённое или пропущенное поле каталога")
            for field, value in fields.items(): texts[f"catalog.{entry_id}.{field}"] = value
    elif resource == "releases":
        if set(author) != {note["version"] for note in source["releases"]}:
            raise ValueError("Неполная/неизвестная версия истории")
        for note in source["releases"]:
            fields = author[note["version"]]
            if set(fields) != {"title", "summary", "features", "improvements", "fixes"}:
                raise ValueError("Защищённое или пропущенное поле истории")
            prefix = f"release.{note['version']}"
            for field in ["title", "summary"]: texts[f"{prefix}.{field}"] = fields[field]
            if set(fields["features"]) != {feature["id"] for feature in note["features"]}:
                raise ValueError("Неполный/неизвестный ID функции")
            for feature_id, translated in fields["features"].items():
                if set(translated) != {"title", "detail"}: raise ValueError("Защищённое или пропущенное поле функции")
                for field, value in translated.items(): texts[f"{prefix}.feature.{feature_id}.{field}"] = value
            for field, key in [("improvement", "improvements"), ("fix", "fixes")]:
                if set(fields[key]) != set(note[key]): raise ValueError("Неполный/неизвестный элемент списка")
                for original, translated in fields[key].items(): texts[value_key(prefix, field, original)] = translated
    else:
        raise ValueError("Неизвестный тип ресурса")
    expected = source_texts(source, resource)
    if set(texts) != set(expected) or any(not isinstance(value, str) or not value.strip() for value in texts.values()):
        raise ValueError("Перевод неполон, содержит пустые или неизвестные поля")
    return dict(formatVersion=1, resource=resource, locale="en", sourceSHA256=source_sha256, status="draft", texts=texts)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    for resource, author, fingerprint in [
        ("catalog", resources_en.CATALOG, resources_en.CATALOG_SHA256),
        ("releases", resources_en.RELEASES, resources_en.RELEASES_SHA256),
    ]:
        source = (root / f"Sources/LearningCore/Resources/{resource}.json").read_bytes()
        document = build(source, resource, author, fingerprint)
        text = json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
        path = root / f"localization/drafts/{resource}.en.json"
        if args.check:
            if not path.exists() or path.read_text() != text:
                raise SystemExit(f"Черновик {resource} не совпадает с авторским переводом")
        else:
            path.write_text(text)
        print(f"{resource}: {len(document['texts'])} полей, полный draft, НЕ reviewed и НЕ ресурс app")


if __name__ == "__main__":
    main()
