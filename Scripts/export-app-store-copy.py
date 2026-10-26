#!/usr/bin/env python3
"""Generate App Store field files and validation from canonical metadata JSON."""
import argparse
import json
from datetime import date
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--source", type=Path, required=True, help="Canonical metadata.json")
parser.add_argument("--output", type=Path, required=True, help="Generated output directory")
parser.add_argument("--platform", default="macOS")
parser.add_argument("--version", default="2.0")
parser.add_argument("--date", default=date.today().isoformat())
args = parser.parse_args()
copy = json.loads(args.source.read_text())
fields = {"name": ("name.txt", 30), "subtitle": ("subtitle.txt", 30),
          "promotional_text": ("promotional-text.txt", 170), "description": ("description.txt", 4000),
          "whats_new": ("whats-new.txt", 4000), "keywords": ("keywords.txt", 100)}
assert set(copy) == {"en-US", "es-ES", "fr-FR", "zh-Hans"}
validation = {"platform": args.platform, "version": args.version, "status": "draft-for-review",
              "date": args.date, "keyword_basis": "proposed name and subtitle in this package", "locales": {}}
for locale, values in copy.items():
    assert set(values) == set(fields), locale
    counts = {}
    for key, (filename, limit) in fields.items():
        text = values[key]
        assert isinstance(text, str) and len(text) <= limit, (locale, key)
        count = {"characters": len(text), "utf8_bytes": len(text.encode("utf-8")), "limit_characters": limit}
        if key == "keywords":
            assert count["utf8_bytes"] <= 100, locale
            count["limit_utf8_bytes"] = 100
        counts[key] = count
    validation["locales"][locale] = counts
args.output.mkdir(parents=True, exist_ok=True)
for locale, values in copy.items():
    directory = args.output / locale
    directory.mkdir(exist_ok=True)
    for key, (filename, _) in fields.items():
        (directory / filename).write_text(values[key] + "\n")
(args.output / "validation.json").write_text(json.dumps(validation, ensure_ascii=False, indent=2) + "\n")
print(f"Generated and validated {len(copy) * len(fields)} field files from {args.source}.")
