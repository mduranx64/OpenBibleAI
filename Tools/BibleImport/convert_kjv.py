import argparse
import json
import re
from pathlib import Path


def parse_verses(text):
    verses = []
    seen = set()

    for line_number, line in enumerate(text.splitlines(), start=1):
        if not line.strip():
            continue

        match = re.fullmatch(r"([A-Z0-9]{3}) ([0-9]+):([0-9]+) (.*)", line)
        if match is None:
            raise ValueError(f"Line {line_number}: invalid verse format")

        book_id, chapter, verse, verse_text = match.groups()
        chapter, verse = int(chapter), int(verse)

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

    return verses


def main():
    parser = argparse.ArgumentParser(description="Convert KJV VPL to verse JSON")
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    if args.source.resolve() == args.output.resolve():
        raise ValueError("Source and output must be different files")

    verses = parse_verses(args.source.read_text(encoding="utf-8-sig"))
    book_count = len({verse["book_id"] for verse in verses})

    if book_count != 66 or len(verses) != 31102:
        raise ValueError(
            f"Expected 66 books and 31102 verses; got {book_count} and {len(verses)}"
        )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(verses, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {len(verses)} verses across {book_count} books to {args.output}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        raise SystemExit(str(error))
