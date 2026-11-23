import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
COURSE = ROOT / "Sources/LearningCore/Resources/course.json"


class UniversityCoverageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        course = json.loads(COURSE.read_text())
        cls.lessons = [lesson for section in course["sections"] for lesson in section["lessons"]]
        cls.by_id = {lesson["id"]: lesson for lesson in cls.lessons}
        cls.ids = ({section["id"] for section in course["sections"]}
                   | set(cls.by_id)
                   | {exercise["id"] for lesson in cls.lessons for exercise in lesson["exercises"]})

    def test_coverage_matrix_links_existing_ids(self):
        matrix = (ROOT / "UNIVERSITY_COVERAGE.md").read_text()
        references = set(re.findall(r"cpp\.[A-Za-z0-9_.-]+", matrix))
        self.assertGreaterEqual(len(references), 25)
        self.assertEqual(references - self.ids, set())

    def test_bit_count_follows_while_and_keeps_stable_id(self):
        ids = [lesson["id"] for lesson in self.lessons]
        self.assertLess(ids.index("cpp.while"), ids.index("cpp.bits"))
        self.assertIn("cpp.bits.bitcount", {exercise["id"] for exercise in self.by_id["cpp.bits"]["exercises"]})

    def test_academic_explanations_are_present(self):
        priority = self.by_id["cpp.priority"]["theory"]
        self.assertIn("только выбранная ветвь", priority)
        self.assertIn("поведение может быть неопределённым", priority)
        self.assertIn("fmod", self.by_id["cpp.cmath"]["theory"])
        self.assertIn("радианах", self.by_id["cpp.cmath"]["theory"])
        self.assertIn("int a[rows][cols]", self.by_id["cpp.matrices"]["theory"])
        self.assertIn("T (*)[N]", self.by_id["cpp.dynamic"]["microscope"])
        self.assertIn("ссылочные могут обращаться к общему объекту", self.by_id["cpp.recursion"]["theory"])

    def test_reference_language_examples_cpp17_and_cpp20(self):
        source = r"""
#include <cmath>
#include <iostream>
#include <type_traits>
void parameter(int data[3]) {
    static_assert(std::is_same_v<decltype(data), int*>);
}
int main() {
    int x = 0;
    int result = true ? ++x : ++x;
    const int fixed = 4;
    auto copy = fixed;
    auto& reference = fixed;
    static_assert(std::is_same_v<decltype(copy), int>);
    static_assert(std::is_same_v<decltype(reference), const int&>);
    int matrix[2][3]{};
    matrix[1][2] = 7;
    parameter(matrix[0]);
    std::cout << result << ' ' << x << ' ' << matrix[1][2] << ' '
              << std::fmod(5.5, 2.0);
}
"""
        root = ROOT / ".build" / "content-check"
        root.mkdir(parents=True, exist_ok=True)
        env = dict(os.environ, DEVELOPER_DIR=os.environ.get("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer"))
        with tempfile.TemporaryDirectory(prefix="upd2-examples-", dir=root) as folder:
            path = Path(folder)
            (path / "example.cpp").write_text(source)
            for standard in ("c++17", "c++20"):
                binary = path / standard
                subprocess.run(["xcrun", "clang++", f"-std={standard}", "-Wall", "-Wextra",
                                "-Werror", "-pedantic-errors", str(path / "example.cpp"),
                                "-o", str(binary)], env=env, check=True, capture_output=True, timeout=45)
                result = subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.stdout, "1 1 7 1.5")


if __name__ == "__main__":
    unittest.main()
