import tempfile
import unittest
from pathlib import Path
from clean_artifacts import candidates
from repository_check import forbidden


class RepositoryToolsTests(unittest.TestCase):
    def test_publication_paths(self):
        for name in ["dist/codelib.app/Contents/Info.plist", ".build/data", ".local-data/progress.json", "x/__pycache__/a.pyc", ".env.local", "x/.DS_Store", "localization/ui/SettingsView.stringsdata"]:
            self.assertTrue(forbidden(name), name)
        for name in ["Sources/LearningCore/Resources/course.json", "localization/drafts/course.en.json", "localization/ui/Localizable.xcstrings", "packaging/CodePath.icns", ".env.example"]:
            self.assertFalse(forbidden(name), name)

    def test_cleanup_preserves_recent_incomplete_and_unknown_runs(self):
        build = Path(__file__).resolve().parents[1] / ".build"
        build.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=build) as temporary:
            root = Path(temporary)
            runs = root / ".build/ui-smoke"
            for name in ["run-20261112-000001", "run-20261112-000002", "run-20261112-000003"]:
                report = runs / name / "screenshots/report.json"
                report.parent.mkdir(parents=True)
                report.write_text("{}")
            (runs / "personal-data").mkdir()
            (runs / "run-20261112-000004").mkdir()  # No report: could still be running.
            paths = candidates(root, keep=2)
            self.assertEqual(len(paths), 1)
            self.assertEqual(paths[0].name, "run-20261112-000001")
            (runs / "run-20261112-000005").symlink_to(runs / "run-20261112-000001", target_is_directory=True)
            self.assertEqual(candidates(root, keep=2), paths)
            with self.assertRaises(ValueError):
                candidates(root, keep=0)


if __name__ == "__main__":
    unittest.main()
