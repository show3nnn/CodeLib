#!/usr/bin/env python3
"""Rebuild the app's offline JSON from explicitly authored lesson modules."""
import json
import argparse
from pathlib import Path
import content_01
import content_02
import content_03
import content_04
import content_05
import content_06
import content_07
import content_08
import content_09
import content_10
import content_11
import content_12
import content_13
import content_14
import content_15
import content_16

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="Check reproducibility without modifying course.json")
    args = parser.parse_args()
    sections = (content_01.sections() + content_02.sections() + content_03.sections()
                + content_04.sections() + content_05.sections() + content_06.sections()
                + content_07.sections() + content_08.sections() + content_09.sections() + content_10.sections()
                + content_11.sections() + content_12.sections() + content_13.sections() + content_14.sections()
                + content_15.sections() + content_16.sections())
    previous = None
    for section in sections:
        for lesson in section["lessons"]:
            lesson["prerequisites"] = [previous] if previous else []
            previous = lesson["id"]
    course = dict(id="cpp-foundations", version=1,
                  title="C++ — с нуля до уверенного первого курса", language="C++", availability="available",
                  summary="Практический курс на C++17: от первой программы до контейнеров, памяти, объектов и консольных проектов. Эталоны проверяются также в C++20.", sections=sections)
    path = Path(__file__).resolve().parents[1] / "Sources/LearningCore/Resources/course.json"
    text = json.dumps(course, ensure_ascii=False, indent=2) + "\n"
    if args.check:
        if not path.exists() or path.read_text() != text:
            raise SystemExit("course.json отличается от авторских модулей. Проверьте изменения и запустите generate_content.py явно.")
    else:
        path.write_text(text)
    lessons = [l for s in sections for l in s["lessons"]]
    exercises = [e for l in lessons for e in l["exercises"]]
    print(f"Контент: {len(sections)} разделов, {len(lessons)} уроков, {len(exercises)} заданий")

if __name__ == "__main__":
    main()
