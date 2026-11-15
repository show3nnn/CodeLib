import tempfile
import unittest
from pathlib import Path
import subprocess
import sys

from check_release_localization import violations


class ReleaseLocalizationTests(unittest.TestCase):
    def make_app(self, root):
        app = root / "codelib.app"
        resources = app / "Contents/Resources"
        resources.mkdir(parents=True)
        (app / "Contents/Info.plist").write_text("fixture")
        (resources / "course.json").write_text("{}")
        return app

    def test_rejects_draft_and_catalog_resources_without_deleting_them(self):
        build = Path(__file__).resolve().parents[1] / ".build"
        build.mkdir(exist_ok=True)
        cases = [
            "Contents/Resources/en.lproj/Localizable.strings",
            "Contents/Resources/en-US.lproj/other.strings",
            "Contents/Resources/en_GB.lproj/other.strings",
            "Contents/Resources/ru.lproj/Localizable.strings",
            "Contents/Resources/Localizable.xcstrings",
            "Contents/Resources/CodePath_LearningCore.bundle/Contents/Resources/course.en.json",
            "Contents/Resources/catalog.en.json",
            "Contents/Resources/catalog.en-GB.json",
            "Contents/Resources/releases.en.json",
            "Contents/MacOS/Extracted.STRINGSData",
        ]
        with tempfile.TemporaryDirectory(dir=build) as temporary:
            root = Path(temporary)
            app = self.make_app(root)
            self.assertEqual(violations(app), [])
            for name in cases:
                with self.subTest(path=name):
                    item = app / name
                    item.parent.mkdir(parents=True, exist_ok=True)
                    item.write_bytes(b"preserve this artifact")
                    self.assertTrue(violations(app))
                    self.assertEqual(item.read_bytes(), b"preserve this artifact")
                    item.unlink()
                    # Remove the now-empty localization directory only within
                    # the isolated fixture, never from a real app bundle.
                    if item.parent.name.lower().endswith(".lproj"):
                        item.parent.rmdir()
            self.assertEqual(violations(app), [])

    def test_rejects_resource_symlinks_and_missing_app(self):
        build = Path(__file__).resolve().parents[1] / ".build"
        build.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=build) as temporary:
            root = Path(temporary)
            app = self.make_app(root)
            external = root / "outside"
            external.mkdir()
            link = app / "Contents/Resources/other.bundle"
            link.symlink_to(external, target_is_directory=True)
            self.assertTrue(any("resource symlink" in item for item in violations(app)))
            self.assertTrue(link.is_symlink())
            with self.assertRaises(ValueError):
                violations(root / "missing.app")

    def test_command_fails_without_removing_contaminated_resource(self):
        project = Path(__file__).resolve().parents[1]
        build = project / ".build"
        build.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=build) as temporary:
            app = self.make_app(Path(temporary))
            item = app / "Contents/Resources/course.en.json"
            item.write_text("draft data")
            result = subprocess.run([sys.executable, str(project / "scripts/check_release_localization.py"), str(app)],
                                    capture_output=True, text=True, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("course.en.json", result.stderr)
            self.assertEqual(item.read_text(), "draft data")


if __name__ == "__main__":
    unittest.main()
