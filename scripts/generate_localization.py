#!/usr/bin/env python3
"""Reproduce a developer-only translation draft; never promote it to an app language."""
import argparse
import json
from pathlib import Path
import content_en_01
from localization_tools import digest, entities, source_texts, value_key


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    source = (root / "Sources/LearningCore/Resources/course.json").read_bytes()
    if digest(source) != content_en_01.SOURCE_SHA256:
        raise SystemExit("Исходный курс изменён: сначала пересмотрите перевод и его source SHA256.")
    course = json.loads(source)
    known = {item["id"]: (item, fields) for item, fields in entities(course)}
    texts = {}
    for entity_id, translated in content_en_01.ENTITIES.items():
        original, fields = known[entity_id]
        allowed = set(fields) | {"hints", "choices"}
        if set(translated) - allowed:
            raise SystemExit(f"Неизвестные поля перевода: {entity_id}")
        for field, value in translated.items():
            if field == "hints":
                if len(value) != len(original["hints"]):
                    raise SystemExit(f"Число подсказок изменилось: {entity_id}")
                for level, hint in enumerate(value, 1):
                    texts[f"{entity_id}.hint.{level}"] = hint
            elif field == "choices":
                if set(value) != set(original["choices"]):
                    raise SystemExit(f"Варианты ответа изменились: {entity_id}")
                for canonical, label in value.items():
                    texts[value_key(entity_id, "choice", canonical)] = label
            else:
                texts[f"{entity_id}.{field}"] = value
        for skill in original.get("skills", []):
            texts[value_key(entity_id, "skill", skill)] = content_en_01.SKILLS[skill]
    expected = source_texts(course)
    if set(texts) - set(expected) or any(not isinstance(v, str) or not v.strip() for v in texts.values()):
        raise SystemExit("Пустые или неизвестные поля в черновике")
    document = dict(formatVersion=1, courseID=course["id"], locale="en", sourceSHA256=digest(source), status="draft", texts=texts)
    path = root / "localization/drafts/course.en.json"
    output = json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.check:
        if not path.exists() or path.read_text() != output:
            raise SystemExit("Черновик перевода отличается от авторского модуля; запустите generate_localization.py.")
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(output)
    print(f"Черновик en: {len(texts)}/{len(expected)} текстовых полей; первый урок, НЕ готовая локализация приложения.")


if __name__ == "__main__":
    main()
