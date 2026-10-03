"""Convert a verse-per-line (VPL) Bible into an OpenBibleAI version package.

Usage:
    python3 Tools/BibleImport/convert_vpl.py Tools/BibleImport/versions/rv1909.json Bibles/

Reads the recipe (version metadata, source file under Tools/BibleImport/Source/,
book-name table, expected counts) and writes `<output>/<id>/version.json`,
`books.json` and `verses.json`. Scripture text is copied unchanged. With
`--compare <verses.json>` it also reports verses missing on either side
(versification differences), e.g. against the KJV. Recipe options:
`skip_empty_verses` leaves out empty verse slots, and `canon_only` leaves
out books outside the 66-book canon (an edition's deuterocanon).
"""

import argparse
import json
import re
from pathlib import Path

IMPORT_DIR = Path(__file__).resolve().parent


def parse_verses(text, skip_empty=False, canon=None):
    """Verses in file order. With `skip_empty`, verse slots without text
    (a source padded to another versification) are left out and returned
    as the second value. With `canon`, books outside it are left out and
    returned as the third value."""
    verses = []
    skipped = []
    dropped = set()
    seen = set()

    for line_number, line in enumerate(text.splitlines(), start=1):
        if not line.strip():
            continue

        match = re.fullmatch(r"([A-Z0-9]{3}) ([0-9]+):([0-9]+) ?(.*)", line)
        if match is None:
            raise ValueError(f"Line {line_number}: invalid verse format")

        book_id, chapter, verse, verse_text = match.groups()
        chapter, verse = int(chapter), int(verse)

        if canon is not None and book_id not in canon:
            dropped.add(book_id)
            continue

        if skip_empty and chapter > 0 and verse > 0 and not verse_text.strip():
            skipped.append((book_id, chapter, verse))
            continue

        if chapter < 1 or verse < 1 or not verse_text.strip():
            raise ValueError(f"Line {line_number}: invalid or empty verse")

        reference = (book_id, chapter, verse)
        if reference in seen:
            raise ValueError(f"Line {line_number}: duplicate {reference}")

        seen.add(reference)
        verses.append({
            "book_id": book_id,
            "chapter": chapter,
            "verse": verse,
            "text": verse_text,
        })

    return verses, skipped, sorted(dropped)


def build_books(verses, names):
    """Books present in the verses, in the table's canonical order."""
    present = {verse["book_id"] for verse in verses}
    unknown = present - names.keys()
    if unknown:
        raise ValueError(f"Book IDs without a name: {sorted(unknown)}")

    return [
        {"book_id": book_id, "name": name, "canonical_order": order}
        for order, (book_id, name) in enumerate(names.items(), start=1)
        if book_id in present
    ]


def versification_report(verses, other):
    ours = {(v["book_id"], v["chapter"], v["verse"]) for v in verses}
    theirs = {(v["book_id"], v["chapter"], v["verse"]) for v in other}
    return sorted(ours - theirs), sorted(theirs - ours)


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description="Convert a VPL Bible to a version package")
    parser.add_argument("recipe", type=Path)
    parser.add_argument("output", type=Path, help="parent folder; the package goes in <output>/<id>")
    parser.add_argument("--compare", type=Path, help="verses.json to compare versification with")
    args = parser.parse_args()

    recipe = json.loads(args.recipe.read_text(encoding="utf-8"))
    version = recipe["version"]
    source = IMPORT_DIR / "Source" / recipe["source"]
    names = json.loads((IMPORT_DIR / "books" / f"{recipe['book_names']}.json").read_text(encoding="utf-8"))

    # `canon_only`: an edition's deuterocanonical/apocryphal books (TOB,
    # 1MA, …) are left out; the app reads the 66-book canon.
    verses, skipped, dropped = parse_verses(
        source.read_text(encoding="utf-8-sig"),
        skip_empty=recipe.get("skip_empty_verses", False),
        canon=names.keys() if recipe.get("canon_only", False) else None,
    )
    books = build_books(verses, names)

    expected = (recipe["expected_books"], recipe["expected_verses"])
    if (len(books), len(verses)) != expected:
        raise ValueError(
            f"Expected {expected[0]} books and {expected[1]} verses; got {len(books)} and {len(verses)}"
        )

    package = args.output / version["id"]
    package.mkdir(parents=True, exist_ok=True)
    write_json(package / "version.json", version)
    write_json(package / "books.json", books)
    write_json(package / "verses.json", verses)
    print(f"Wrote {len(verses)} verses across {len(books)} books to {package}")
    if dropped:
        print(f"Left out {len(dropped)} books outside the canon: {', '.join(dropped)}")
    if skipped:
        print(f"Skipped {len(skipped)} empty verse slots: " + ", ".join(f"{b} {c}:{v}" for b, c, v in skipped))

    if args.compare:
        only_here, only_there = versification_report(
            verses, json.loads(args.compare.read_text(encoding="utf-8"))
        )
        print(f"Versification vs {args.compare}: {len(only_here)} only here, {len(only_there)} only there")
        for book_id, chapter, verse in (only_here + only_there)[:50]:
            print(f"  {book_id} {chapter}:{verse}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        raise SystemExit(str(error))
