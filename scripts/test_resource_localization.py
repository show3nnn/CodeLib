import copy
import json
from pathlib import Path
import re
import unittest
from generate_resource_localization import build, source_texts
from localization_tools import digest
import resources_en


class ResourceTranslationTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(__file__).resolve().parents[1]

    def fixture(self, resource):
        data = (self.root / f"Sources/LearningCore/Resources/{resource}.json").read_bytes()
        author = resources_en.CATALOG if resource == "catalog" else resources_en.RELEASES
        fingerprint = resources_en.CATALOG_SHA256 if resource == "catalog" else resources_en.RELEASES_SHA256
        return data, copy.deepcopy(author), fingerprint

    def test_complete_drafts_are_reproducible_and_not_promoted(self):
        for resource, count in [("catalog", 10), ("releases", 198)]:
            data, author, fingerprint = self.fixture(resource)
            document = build(data, resource, author, fingerprint)
            self.assertEqual(len(document["texts"]), count)
            self.assertEqual(set(document["texts"]), set(source_texts(json.loads(data), resource)))
            self.assertEqual(document["status"], "draft")
            self.assertFalse(any(re.search("[А-Яа-яЁё]", value) for value in document["texts"].values()))
            if resource == "releases":
                self.assertFalse(any(re.search(r"\\u[0-9a-fA-F]{4}", value) for value in document["texts"].values()))
            self.assertEqual(document, json.loads((self.root / f"localization/drafts/{resource}.en.json").read_text()))

    def test_holes_empty_unknown_and_protected_fields_are_rejected(self):
        for resource in ["catalog", "releases"]:
            data, author, fingerprint = self.fixture(resource)
            first = next(iter(author))
            variants = []
            missing = copy.deepcopy(author)
            del missing[first]["summary"]
            variants.append(missing)
            empty = copy.deepcopy(author)
            empty[first]["title"] = " "
            variants.append(empty)
            protected = copy.deepcopy(author)
            protected[first]["availability" if resource == "catalog" else "date"] = "changed"
            variants.append(protected)
            unknown = copy.deepcopy(author)
            unknown["future.unknown"] = author[first]
            variants.append(unknown)
            for invalid in variants:
                with self.subTest(resource=resource, author=invalid):
                    with self.assertRaises(ValueError): build(data, resource, invalid, fingerprint)
        data, author, fingerprint = self.fixture("releases")
        author["0.1.0"]["features"]["course"]["symbol"] = "must not change"
        with self.assertRaises(ValueError): build(data, "releases", author, fingerprint)

    def test_stale_fingerprints_and_missing_list_translations_are_rejected(self):
        for resource in ["catalog", "releases"]:
            data, author, fingerprint = self.fixture(resource)
            with self.assertRaises(ValueError): build(data + b"\n", resource, author, fingerprint)
        data, author, fingerprint = self.fixture("releases")
        author["0.1.6"]["fixes"].clear()
        with self.assertRaises(ValueError): build(data, "releases", author, fingerprint)

    def test_reordering_does_not_change_translation_keys(self):
        for resource in ["catalog", "releases"]:
            data, author, fingerprint = self.fixture(resource)
            original = build(data, resource, author, fingerprint)["texts"]
            source = json.loads(data)
            if resource == "catalog":
                source["entries"].reverse()
            else:
                for note in source["releases"]:
                    for field in ["features", "improvements", "fixes"]: note[field].reverse()
            reordered = json.dumps(source, ensure_ascii=False).encode()
            # Synthetic source-review fixture only: never update the author's pinned fingerprint.
            translated = build(reordered, resource, author, digest(reordered))["texts"]
            self.assertEqual(original, translated)

    def test_grading_release_shortcut_matches_editor(self):
        data, author, _ = self.fixture("releases")
        note = next(note for note in json.loads(data)["releases"] if note["version"] == "0.4.0")
        detail = next(feature["detail"] for feature in note["features"] if feature["id"] == "grading")
        self.assertIn("Command-Shift-Return", detail)
        self.assertIn("Command-Shift-Return", author["0.4.0"]["features"]["grading"]["detail"])
        editor = (self.root / "Sources/CodePath/LessonView.swift").read_text()
        self.assertRegex(editor, r'Button\("Проверить решение"[^}]+\}[\s\S]{0,160}?'
                                 r'\.keyboardShortcut\(\.return, modifiers: \[\.command, \.shift\]\)')


if __name__ == "__main__":
    unittest.main()
