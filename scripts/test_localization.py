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


NUMBER = re.compile(r"(?<![\w])[-−]?\d+(?:[.,]\d+)?(?![\w])")
COMPARISON = re.compile(r"(?<![<>=!])(?:<=|>=|==|!=|≤|≥)(?![=<>])")


def numeric_tokens(text):
    return Counter(value.replace("−", "-").replace(",", ".") for value in NUMBER.findall(text))


def comparison_tokens(text):
    return Counter({"≤": "<=", "≥": ">="}.get(value, value) for value in COMPARISON.findall(text))


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
        texts, _ = generator.build_texts(self.course, self.source)
        for section in self.course["sections"]:
            for lesson in section["lessons"]:
                for exercise in lesson["exercises"]:
                    with self.subTest(exercise=exercise["id"]):
                        self.assertEqual(numeric_tokens(exercise["prompt"]), numeric_tokens(texts[f'{exercise["id"]}.prompt']))

    def test_numeric_token_guard_preserves_sign_and_repetition(self):
        self.assertEqual(numeric_tokens("−12 3,5 -12"), Counter({"-12": 2, "3.5": 1}))
        self.assertNotEqual(numeric_tokens("0 10 10"), numeric_tokens("0 10"))
        self.assertNotEqual(numeric_tokens("−12"), numeric_tokens("12"))

    def test_theory_hints_and_explanations_keep_numeric_tokens(self):
        # Known reviewed tokenization differences, not omissions of meaning:
        # number words, the English plural "2s", an explanatory repeated 60,
        # and comma-separated indices interpreted as decimal commas.
        exceptions = {
            "cpp.while.theory": ({"0": 1}, {}),
            "cpp.types.microscope": ({"2": 1}, {}),
            "cpp.while.recap": ({"0": 1}, {}),
            "cpp.inventory.compress.explanation": ({"2": 1}, {}),
            "cpp.division.clock.hint.2": ({}, {"60": 1}),
            "cpp.arrays.reverse.hint.1": ({"0.1": 1}, {"0": 1, "1": 1}),
            "cpp.arrays.reverse.hint.2": ({"2.1": 1}, {"2": 1, "1": 1}),
        }
        texts, source = generator.build_texts(self.course, self.source)
        observed = {}
        for key, original in source.items():
            if key.endswith((".theory", ".microscope", ".recap", ".explanation")) or ".hint." in key:
                missing = numeric_tokens(original) - numeric_tokens(texts[key])
                added = numeric_tokens(texts[key]) - numeric_tokens(original)
                if missing or added:
                    observed[key] = (dict(missing), dict(added))
        self.assertEqual(observed, exceptions)

    def test_explicit_comparison_operators_remain_in_translation(self):
        # Standalone < and > are deliberately excluded: they also delimit C++
        # headers and templates. This guard does not establish semantic equivalence.
        texts, source = generator.build_texts(self.course, self.source)
        for key, original in source.items():
            if key.endswith((".prompt", ".theory", ".microscope", ".recap", ".explanation")) or ".hint." in key or ".choice." in key:
                with self.subTest(field=key):
                    self.assertEqual(comparison_tokens(original), comparison_tokens(texts[key]))

    def test_choice_labels_keep_numeric_tokens(self):
        texts, source = generator.build_texts(self.course, self.source)
        for key, original in source.items():
            if ".choice." in key:
                with self.subTest(field=key):
                    self.assertEqual(numeric_tokens(original), numeric_tokens(texts[key]))

    def test_comparison_guard_distinguishes_boundary_and_equality(self):
        self.assertEqual(comparison_tokens("x ≤ 3 && y >= 2"), Counter({"<=": 1, ">=": 1}))
        self.assertNotEqual(comparison_tokens("x <= 3"), comparison_tokens("x >= 3"))
        self.assertNotEqual(comparison_tokens("x == 3"), comparison_tokens("x != 3"))
        self.assertEqual(comparison_tokens("#include <vector>  a < b  a <=> b"), Counter())

    def test_cpp_standard_library_names_are_not_lost_in_translation(self):
        # Identifiers are language-neutral; additional English examples are allowed.
        # This only checks spelling/presence and is not a semantic correctness review.
        identifier = re.compile(r"\bstd::[A-Za-z_][A-Za-z_0-9]*")
        texts, expected = generator.build_texts(self.course, self.source)
        for key, original in expected.items():
            if key.endswith((".theory", ".prompt", ".explanation", ".microscope", ".recap")) or ".hint." in key:
                with self.subTest(field=key):
                    self.assertFalse(set(identifier.findall(original)) - set(identifier.findall(texts[key])))

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
