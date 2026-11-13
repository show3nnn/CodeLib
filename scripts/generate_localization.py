#!/usr/bin/env python3
"""Reproduce a developer-only translation draft; never promote it to an app language."""
import argparse
import json
from pathlib import Path
import content_en_01
import content_en_02
import content_en_03
import content_en_04
import content_en_05
import content_en_06
import content_en_07
import content_en_08
import content_en_09
import content_en_10
import content_en_11
import content_en_12
import content_en_13
import content_en_14
import content_en_15
import content_en_16
import content_en_17
from localization_tools import digest, entities, source_texts, value_key

AUTHORS = [content_en_01, content_en_02, content_en_03, content_en_04, content_en_05, content_en_06, content_en_07, content_en_08,
           content_en_09, content_en_10, content_en_11, content_en_12, content_en_13, content_en_14,
           content_en_15, content_en_16, content_en_17]


def build_texts(course, source):
    known = {item["id"]: (item, fields) for item, fields in entities(course)}
    texts, seen = {}, set()
    for author in AUTHORS:
        if digest(source) != author.SOURCE_SHA256:
            raise ValueError(f"Исходный курс изменён: сначала пересмотрите {author.__name__} и его SHA256.")
        for entity_id, translated in author.ENTITIES.items():
            if entity_id in seen:
                raise ValueError(f"Повторный ID перевода: {entity_id}")
            seen.add(entity_id)
            original, fields = known[entity_id]
            allowed = set(fields) | {"hints", "choices"}
            if set(translated) - allowed:
                raise ValueError(f"Неизвестные поля перевода: {entity_id}")
            for field, value in translated.items():
                if field == "hints":
                    if len(value) != len(original["hints"]):
                        raise ValueError(f"Число подсказок изменилось: {entity_id}")
                    for level, hint in enumerate(value, 1):
                        texts[f"{entity_id}.hint.{level}"] = hint
                elif field == "choices":
                    if set(value) != set(original["choices"]):
                        raise ValueError(f"Варианты ответа изменились: {entity_id}")
                    for canonical, label in value.items():
                        texts[value_key(entity_id, "choice", canonical)] = label
                else:
                    texts[f"{entity_id}.{field}"] = value
            for skill in original.get("skills", []):
                texts[value_key(entity_id, "skill", skill)] = author.SKILLS[skill]
    expected = source_texts(course)
    if set(texts) - set(expected) or any(not isinstance(v, str) or not v.strip() for v in texts.values()):
        raise ValueError("Пустые или неизвестные поля в черновике")
    selected_ids = [author.SECTION_ID for author in AUTHORS]
    selected = [s for s in course["sections"] if s["id"] in selected_ids]
    if len(selected) != len(selected_ids):
        raise ValueError("Отсутствующий или повторный ID переводимого раздела")
    required = source_texts(dict(course, sections=selected))
    missing = set(required) - set(texts)
    if missing:
        raise ValueError(f"Перевод разделов не завершён: {sorted(missing)}")
    return texts, expected


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    source = (root / "Sources/LearningCore/Resources/course.json").read_bytes()
    course = json.loads(source)
    texts, expected = build_texts(course, source)
    document = dict(formatVersion=1, courseID=course["id"], locale="en", sourceSHA256=digest(source), status="draft", texts=texts)
    path = root / "localization/drafts/course.en.json"
    output = json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.check:
        if not path.exists() or path.read_text() != output:
            raise SystemExit("Черновик перевода отличается от авторского модуля; запустите generate_localization.py.")
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(output)
    section_ids = {author.SECTION_ID for author in AUTHORS}
    sections = [section for section in course["sections"] if section["id"] in section_ids]
    lessons = [lesson for section in sections for lesson in section["lessons"]]
    tasks = [task for lesson in lessons for task in lesson["exercises"]]
    print(f"Черновик en: {len(texts)}/{len(expected)} текстовых полей; {len(sections)} разделов / {len(lessons)} уроков / {len(tasks)} задач, НЕ готовая локализация приложения.")


if __name__ == "__main__":
    main()
