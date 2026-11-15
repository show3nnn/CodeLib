#!/usr/bin/env python3
"""Fail closed if developer-only localization resources enter a release bundle."""
import argparse
import os
from pathlib import Path
import re


ENGLISH_LPROJ = re.compile(r"^en(?:[-_][a-z0-9]+)*\.lproj$", re.IGNORECASE)
ENGLISH_CONTENT = re.compile(r"^(?:course|catalog|releases)\.en(?:[-_][a-z0-9]+)*\.json$", re.IGNORECASE)
FORBIDDEN_NAMES = {
    "localizable.xcstrings", "localizable.strings", "localizable.stringsdict",
}


def violations(app: Path) -> list[str]:
    contents = app / "Contents"
    resources = contents / "Resources"
    if contents.is_symlink() or not (contents / "Info.plist").is_file() or not resources.is_dir():
        raise ValueError(f"Not a packaged app with Contents/Resources: {app}")
    errors = []
    def raise_walk_error(error: OSError) -> None:
        raise error

    for directory, dirs, files in os.walk(contents, followlinks=False, onerror=raise_walk_error):
        for name in dirs + files:
            path = Path(directory) / name
            relative = path.relative_to(app)
            # A resource symlink could conceal a localized directory outside the
            # bundle; do not follow it or mutate it during this check.
            if path.is_symlink() and (path == resources or resources in path.parents):
                errors.append(f"{relative}: resource symlink cannot be inspected")
            if (ENGLISH_LPROJ.fullmatch(name) or ENGLISH_CONTENT.fullmatch(name) or name.lower() in FORBIDDEN_NAMES
                    or name.lower().endswith(".stringsdata")):
                errors.append(str(relative))
    return sorted(errors)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    try:
        errors = violations(args.app)
    except (OSError, ValueError) as error:
        parser.exit(1, f"Release localization check failed: {error}\n")
    if errors:
        parser.exit(1, "Release localization check failed; developer-only resources remain:\n"
                    + "\n".join(f"  {path}" for path in errors) + "\n")
    print("Release localization check: no developer-only English or UI catalog resources")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
