#!/usr/bin/env python3
"""Extract changelog section for a given version from CHANGELOG.md."""
import re
import sys
import os


def main():
    version = os.environ.get("VERSION", "")
    if not version:
        version = (sys.argv[1] if len(sys.argv) > 1 else "").lstrip("v")

    changelog_path = os.environ.get("CHANGELOG_PATH", "CHANGELOG.md")
    if not os.path.exists(changelog_path):
        print("See CHANGELOG.md for details.", end="")
        return

    try:
        with open(changelog_path, encoding="utf-8") as f:
            content = f.read()
    except Exception:
        print("See CHANGELOG.md for details.", end="")
        return

    if not version:
        print("See CHANGELOG.md for details.", end="")
        return

    pattern = r"## \[" + re.escape(version) + r"\].*?(?=\n## \[|\Z)"
    match = re.search(pattern, content, re.DOTALL)
    if match:
        print(match.group(0).strip(), end="")
    else:
        print("See CHANGELOG.md for details.", end="")


if __name__ == "__main__":
    main()
