#!/usr/bin/env python3
"""Conservative cleanup of completed developer runs. Dry-run unless --apply is supplied."""
import argparse
from pathlib import Path
import re
import shutil


def candidates(root, keep):
    if not 1 <= keep <= 100:
        raise ValueError("Нужно сохранить от 1 до 100 последних запусков")
    build = root / ".build"
    if build.is_symlink():
        raise ValueError(".build — символьная ссылка; автоматическая очистка запрещена")
    plans = []
    for relative, pattern, marker in [
        ("ui-smoke", r"run-\d{8}-\d{6}", "screenshots/report.json"),
        ("release-launch", r"(?:[a-z]+-)*[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}", "report.json"),
    ]:
        folder = build / relative
        if not folder.exists():
            continue
        if folder.is_symlink():
            raise ValueError(f"{folder} — символьная ссылка; очистка запрещена")
        runs = [path for path in folder.iterdir() if not path.is_symlink() and path.is_dir()
                and re.fullmatch(pattern, path.name) and (path / marker).is_file()]
        runs.sort(key=lambda path: (path.stat().st_mtime_ns, path.name), reverse=True)
        plans.extend(runs[keep:])
    return plans


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Удалить перечисленные завершённые прогоны")
    parser.add_argument("--keep", type=int, default=2, help="Сколько последних прогонов каждого вида оставить (по умолчанию 2)")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    paths = candidates(root, args.keep)
    size = sum(item.stat().st_size for path in paths for item in path.rglob("*") if item.is_file() and not item.is_symlink())
    for path in paths:
        print(("Удаляется: " if args.apply else "План: ") + str(path.relative_to(root)))
        if args.apply:
            # Recheck before deleting: only the exact generated run, never the enclosing folder.
            if path.is_symlink() or not path.resolve().is_relative_to(root / ".build"):
                raise ValueError("Путь изменился; очистка остановлена")
            shutil.rmtree(path)
    print(f"{'Удалено' if args.apply else 'Можно освободить'}: {size / 1024**2:.1f} МиБ; последних запусков каждого вида сохранено: {args.keep}.")
    print("Исходники, dist/codelib.app, кеши и пользовательские данные не затрагиваются.")


if __name__ == "__main__":
    main()
