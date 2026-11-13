#!/usr/bin/env python3
"""Check the current Git index and nonignored files, not private data or Git history."""
from pathlib import Path, PurePosixPath
import subprocess


def forbidden(path):
    item = PurePosixPath(path)
    if any(part in {".build", "dist", ".local-data", "__pycache__", "xcuserdata"} for part in item.parts):
        return True
    if any(part.endswith((".app", ".xcresult")) for part in item.parts):
        return True
    return item.name == ".DS_Store" or item.suffix in {".pyc", ".pyo", ".xcuserstate"} or (item.name.startswith(".env") and item.name != ".env.example")


def main():
    root = Path(__file__).resolve().parents[1]
    output = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=root)
    paths = sorted(set(part.decode("utf-8") for part in output.split(b"\0") if part))
    problems = []
    for name in paths:
        path = root / name
        if forbidden(name):
            problems.append(f"Артефакт или локальные данные: {name}")
        elif path.is_file() and not path.is_symlink() and path.stat().st_size > 20 * 1024 * 1024:
            problems.append(f"Файл больше 20 МиБ, проверьте перед публикацией: {name}")
    if problems:
        raise SystemExit("\n".join(problems))
    print(f"Git: {len(paths)} исходных файлов проверено; сборок, локального прогресса и кешей в публикуемом наборе нет.")
    print("Это проверка текущих путей/размеров, не сканер секретов и не аудит истории Git.")


if __name__ == "__main__":
    main()
