import copy
from collections import Counter
import json
from pathlib import Path
import re
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import generate_localization as generator
from localization_tools import source_texts


class LocalizationAuthoringTests(unittest.TestCase):
    def setUp(self):
        root = Path(__file__).resolve().parents[1]
        self.source = (root / "Sources/LearningCore/Resources/course.json").read_bytes()
        self.course = json.loads(self.source)

    def clone(self, author):
        return SimpleNamespace(__name__="test-author", SOURCE_SHA256=author.SOURCE_SHA256,
                               SECTION_ID=author.SECTION_ID, ENTITIES=copy.deepcopy(author.ENTITIES), SKILLS=dict(author.SKILLS))

    def test_entire_course_has_complete_english_prose(self):
        texts, expected = generator.build_texts(self.course, self.source)
        self.assertEqual(len(texts), 2904)
        self.assertEqual(len(expected), 2904)
        selected = [s for s in self.course["sections"] if s["id"] in {a.SECTION_ID for a in generator.AUTHORS}]
        self.assertEqual(len(selected), 17)
        self.assertEqual(sum(len(s["lessons"]) for s in selected), 64)
        self.assertEqual(sum(len(l["exercises"]) for s in selected for l in s["lessons"]), 296)
        self.assertEqual(set(texts), set(source_texts(dict(self.course, sections=selected))))
        self.assertTrue(all(not re.search("[А-Яа-яЁё]", text) for text in texts.values()))
        root = Path(__file__).resolve().parents[1]
        document = json.loads((root / "localization/drafts/course.en.json").read_text())
        self.assertEqual(document["status"], "draft")
        self.assertEqual(document["texts"], texts)

    def test_every_declared_section_rejects_a_hole(self):
        for index, original in enumerate(generator.AUTHORS):
            with self.subTest(section=original.SECTION_ID):
                author = self.clone(original)
                lesson_id = next(key for key, value in author.ENTITIES.items() if "theory" in value)
                del author.ENTITIES[lesson_id]["theory"]
                authors = list(generator.AUTHORS)
                authors[index] = author
                with patch.object(generator, "AUTHORS", authors):
                    with self.assertRaises(ValueError): generator.build_texts(self.course, self.source)

    def test_exercise_prompt_numeric_tokens_match_source(self):
        # This is a narrow guard for examples and bounds, not semantic review:
        # punctuation and decimal separators may differ, but numbers must not vanish.
        number = re.compile(r"(?<![\w])[-−]?\d+(?:[.,]\d+)?(?![\w])")
        def numbers(text):
            return Counter(value.replace("−", "-").replace(",", ".") for value in number.findall(text))

        texts, _ = generator.build_texts(self.course, self.source)
        for section in self.course["sections"]:
            for lesson in section["lessons"]:
                for exercise in lesson["exercises"]:
                    with self.subTest(exercise=exercise["id"]):
                        self.assertEqual(numbers(exercise["prompt"]), numbers(texts[f'{exercise["id"]}.prompt']))

    def test_duplicate_authors_and_protected_fields_are_rejected(self):
        with patch.object(generator, "AUTHORS", [*generator.AUTHORS, generator.AUTHORS[0]]):
            with self.assertRaises(ValueError): generator.build_texts(self.course, self.source)
        author = self.clone(generator.AUTHORS[0])
        author.ENTITIES["cpp.first.beacon"]["solution"] = "must not alter C++"
        with patch.object(generator, "AUTHORS", [author, generator.AUTHORS[1]]):
            with self.assertRaises(ValueError): generator.build_texts(self.course, self.source)

    def test_declared_section_cannot_have_holes_or_blank_text(self):
        author = self.clone(generator.AUTHORS[1])
        del author.ENTITIES["cpp.types"]["microscope"]
        with patch.object(generator, "AUTHORS", [generator.AUTHORS[0], author]):
            with self.assertRaises(ValueError): generator.build_texts(self.course, self.source)
        author = self.clone(generator.AUTHORS[1])
        author.ENTITIES["cpp.types"]["microscope"] = " \n"
        with patch.object(generator, "AUTHORS", [generator.AUTHORS[0], author]):
            with self.assertRaises(ValueError): generator.build_texts(self.course, self.source)

    def test_source_changes_require_review_not_silent_regeneration(self):
        with self.assertRaises(ValueError): generator.build_texts(self.course, self.source + b"\n")


if __name__ == "__main__":
    unittest.main()
