#!/usr/bin/env python3
"""Developer-only reference checks. Never part of the application or user-code execution."""
import concurrent.futures
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
from algorithm_lab_cases import cases as algorithm_lab_cases

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".build/content-check"

def check(item):
    identifier, source, cases = item
    folder = OUT / identifier
    folder.mkdir(parents=True, exist_ok=True)
    cpp = folder / "reference.cpp"
    cpp.write_text(source)
    total = 0
    env = dict(os.environ, DEVELOPER_DIR=os.environ.get("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer"),
               CLANG_MODULE_CACHE_PATH=str(ROOT / ".build/clang-cache"), TMPDIR=str(OUT))
    for standard in ["c++17", "c++20"]:
        binary = folder / standard
        subprocess.run(["xcrun", "clang++", f"-std={standard}", "-Wall", "-Wextra", "-Werror",
                        "-pedantic-errors", "-fsanitize=undefined", "-fno-sanitize-recover=all",
                        str(cpp), "-o", str(binary)], check=True, capture_output=True, text=True, env=env, timeout=45)
        for index, case in enumerate(cases):
            # Every fixture run is isolated, including across repeated verification invocations.
            import tempfile
            run_folder = Path(tempfile.mkdtemp(prefix=f"{standard}-{index}-", dir=folder))
            def safe_file(name):
                path = Path(name)
                if path.is_absolute() or ".." in path.parts:
                    raise ValueError(f"Unsafe fixture path: {name}")
                return run_folder / path
            for name, text in case.get("files", {}).items():
                path = safe_file(name)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)
            # The first sanitized binaries of a run can pay a cold start on a loaded
            # machine; a reference program still has a bounded, generous deadline.
            run = subprocess.run([str(binary)], input=case["input"], capture_output=True, text=True,
                                 timeout=10, check=True, env=env, cwd=run_folder)
            if run.stdout != case["output"] or run.stderr:
                raise ValueError(f"{identifier} {standard}: expected {case['output']!r}, got {run.stdout!r}, stderr {run.stderr!r}")
            for name, expected in case.get("expectedFiles", {}).items():
                actual = safe_file(name).read_text()
                if actual != expected:
                    raise ValueError(f"{identifier}: file {name}: expected {expected!r}, got {actual!r}")
            total += 1
    return total

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    course = json.loads((ROOT / "Sources/LearningCore/Resources/course.json").read_text())
    parser = argparse.ArgumentParser()
    parser.add_argument("--section", choices=[section["id"] for section in course["sections"]], help="Проверить один раздел, не перезаписывая общий отчёт")
    args = parser.parse_args()
    items = []
    differential = algorithm_lab_cases()
    all_ids = {task["id"] for section in course["sections"] for lesson in section["lessons"] for task in lesson["exercises"] if task["solution"]}
    missing = set(differential) - all_ids
    if missing:
        raise ValueError(f"Неизвестные ID дифференциальных проверок: {sorted(missing)}")
    for section in course["sections"]:
        if args.section and section["id"] != args.section:
            continue
        for lesson in section["lessons"]:
            items.append((lesson["id"] + ".example", lesson["example"], []))
            for task in lesson["exercises"]:
                if task["solution"]:
                    items.append((task["id"], task["solution"], task["testCases"] + differential.get(task["id"], [])))
    failures = []
    runs = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        futures = {pool.submit(check, item): item[0] for item in items}
        for future in concurrent.futures.as_completed(futures):
            try:
                runs += future.result()
            except Exception as error:
                message = f"{futures[future]}: {error}"
                if isinstance(error, subprocess.CalledProcessError):
                    message += "\n" + error.stderr
                failures.append(message)
    report = dict(sourcePrograms=len(items), standards=["c++17", "c++20"], executedCases=runs, failures=failures)
    report_name = f"report-{args.section}.json" if args.section else "report.json"
    (OUT / report_name).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return bool(failures)

if __name__ == "__main__":
    sys.exit(main())
