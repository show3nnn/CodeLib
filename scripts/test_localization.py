import copy
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

    def test_two_complete_sections_and_english_prose(self):
        texts, expected = generator.build_texts(self.course, self.source)
        self.assertEqual(len(texts), 380)
        self.assertEqual(len(expected), 2904)
        selected = [s for s in self.course["sections"] if s["id"] in {a.SECTION_ID for a in generator.AUTHORS}]
        self.assertEqual(sum(len(s["lessons"]) for s in selected), 8)
        self.assertEqual(sum(len(l["exercises"]) for s in selected for l in s["lessons"]), 40)
        self.assertEqual(set(texts), set(source_texts(dict(self.course, sections=selected))))
        self.assertTrue(all(not re.search("[А-Яа-яЁё]", text) for text in texts.values()))

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
