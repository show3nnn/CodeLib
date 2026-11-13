import json
from pathlib import Path
import unittest
from generate_ui_localization import catalog, placeholders, source_files
import ui_en


class UICatalogTests(unittest.TestCase):
    def test_compiler_manifest_matches_sources_and_authoring(self):
        root = Path(__file__).resolve().parents[1]
        manifest = json.loads((root / "localization/ui/extraction.json").read_text())
        self.assertEqual(manifest["sourceFiles"], source_files(root))
        value = catalog(manifest, ui_en.TEXTS)
        self.assertEqual(value["sourceLanguage"], "ru")
        self.assertEqual(len(ui_en.TEXTS), 76)
        self.assertTrue(len(value["strings"]) > len(ui_en.TEXTS))
        self.assertTrue(all(not location.startswith("/") for locations in manifest["entries"].values() for location in locations))

    def test_unknown_empty_and_changed_placeholders_are_rejected(self):
        manifest = dict(entries={"Код: %lld пт": ["Sources/CodePath/SettingsView.swift:1"]})
        for translations in [{"unknown": "Unknown"}, {"Код: %lld пт": " "}, {"Код: %lld пт": "Code: %@ pt"}]:
            with self.assertRaises(ValueError): catalog(manifest, translations)
        self.assertEqual(placeholders("%lld / %lld"), placeholders("%lld of %lld"))
        self.assertNotEqual(placeholders("%02lld %.2f %%"), placeholders("%lld %.3f %%"))
        self.assertEqual(catalog(manifest, {"Код: %lld пт": "Code: %lld pt"})["version"], "1.0")


if __name__ == "__main__":
    unittest.main()
