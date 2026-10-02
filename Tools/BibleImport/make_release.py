"""Print the pinned catalog entry and the GitHub release commands for
version packages built by convert_vpl.py (plus embeddings.bin).

Usage:
    python3 Tools/BibleImport/make_release.py Bibles/kjv [Bibles/rv1909 ...]

Each package is published as its own release, tagged `bible-<id>-<n>`, with
the four package files as assets. Paste the Swift into
OpenBibleAI/Features/BibleLibrary/BibleCatalogEntry+Published.swift and run the
printed `gh` commands yourself (publishing is a manual step).
"""

import hashlib
import json
import sys
from pathlib import Path

FILES = ["version.json", "books.json", "verses.json", "embeddings.bin"]
REPOSITORY = "mduranx64/OpenBibleAI"
RELEASE_NUMBER = 1


def swift_string(text):
    return json.dumps(text, ensure_ascii=False)


def main(directories):
    entries, commands = [], []
    for directory in map(Path, directories):
        version = json.loads((directory / "version.json").read_text(encoding="utf-8"))
        missing = [name for name in FILES if not (directory / name).exists()]
        if missing:
            raise SystemExit(f"{directory}: missing {', '.join(missing)}")

        tag = f"bible-{version['id']}-{RELEASE_NUMBER}"
        files = []
        for name in FILES:
            data = (directory / name).read_bytes()
            files.append(
                f'            .init(name: "{name}", size: {len(data):_}, '
                f'sha256: "{hashlib.sha256(data).hexdigest()}"),'
            )
        entries.append("\n".join([
            "        published(",
            f"            id: {swift_string(version['id'])},",
            f"            name: {swift_string(version['name'])},",
            f"            abbreviation: {swift_string(version['abbreviation'])},",
            f"            language: {swift_string(version['language'])},",
            f"            copyright: {swift_string(version['copyright'])},",
            f"            tag: {swift_string(tag)},",
            "            files: [",
            *["    " + line for line in files],
            "            ]",
            "        ),",
        ]))
        assets = " ".join(str(directory / name) for name in FILES)
        commands.append(
            f'gh release create {tag} --repo {REPOSITORY} --title "{version["name"]} ({version["abbreviation"]})" '
            f'--notes "{version["name"]}. {version["copyright"]}." {assets}'
        )

    print("// Catalog entries:\n")
    print("\n".join(entries))
    print("\n# Release commands (run manually):\n")
    print("\n".join(commands))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    main(sys.argv[1:])
