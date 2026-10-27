#!/usr/bin/env python3
"""Copy the latest verified final iPhone media to the user's delivery folder."""
import argparse
import hashlib
import json
import shutil
import struct
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--destination", type=Path, default=Path("/tmp/Tildone-iPhone-App-Store-Finals"))
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
captures = repo / "Marketing/Preview/Output/iOS/captures"
media = repo / "Marketing/Preview/Output/iOS-App-Store"
history = repo / "Marketing/Preview/Output/iOS/revisions/delivery-history"
destination = args.destination.absolute()
assert not destination.is_symlink(), "The delivery folder must not be a symlink."
locales = ["en-US", "es-ES", "fr-FR", "zh-Hans"]
assets = [f"screenshot-{n}" for n in range(1, 7)] + ["preview-1", "preview-2"]
files = []

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

for locale in locales:
    for asset in assets:
        result = json.loads((captures / asset / locale / "export-result.json").read_text())
        source = Path(result["file"])
        suffix = ".png" if asset.startswith("screenshot-") else ".mp4"
        assert result["verified"] and not result.get("draft", False) and result["asset"] == asset and result["locale"] == locale
        assert source.parent == media and source.suffix == suffix and source.is_file()
        assert digest(source) == result["sha256"], source
        group = "Screenshots" if suffix == ".png" else "Previews"
        relative = Path(locale) / group / source.name
        files.append((source, relative, result["sha256"]))

assert len(files) == 32
creative_count = 0
for locale in locales:
    for asset, dimensions in [("header", (3840, 1646)), ("search-results", (3840, 2560))]:
        path = captures / asset / locale / "export-result.json"
        if not path.exists():
            continue
        result = json.loads(path.read_text())
        source = Path(result["file"])
        assert result["verified"] and result["approved"] and not result.get("draft", True)
        assert result["asset"] == asset and result["locale"] == locale
        assert source.parent == media and source.suffix == ".png" and digest(source) == result["sha256"]
        assert struct.unpack(">IIBB", source.read_bytes()[16:26]) == (*dimensions, 8, 2)
        files.append((source, Path(locale) / "Creative" / source.name, result["sha256"]))
        creative_count += 1
expected = {str(relative) for _, relative, _ in files}
if destination.exists():
    unexpected = [str(p.relative_to(destination)) for p in destination.rglob("*")
                  if p.is_symlink() or (p.is_file() and p.name != ".DS_Store"
                                       and str(p.relative_to(destination)) not in expected)]
    assert not unexpected, f"Preserving unrelated contents: {unexpected}"

for source, relative, expected_hash in files:
    target = destination / relative
    assert not target.is_symlink()
    assert not target.parent.is_symlink() and not target.parent.parent.is_symlink()
    if target.is_file():
        previous_hash = digest(target)
        if previous_hash == expected_hash:
            continue
        previous = history / previous_hash / relative
        previous.parent.mkdir(parents=True, exist_ok=True)
        if previous.exists():
            assert digest(previous) == previous_hash
        else:
            shutil.copy2(target, previous)
            assert digest(previous) == previous_hash
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + ".copying")
    assert not temporary.exists() and not temporary.is_symlink()
    shutil.copy2(source, temporary)
    assert digest(temporary) == expected_hash
    temporary.replace(target)

assert {str(p.relative_to(destination)) for p in destination.rglob("*")
        if p.is_file() and p.name != ".DS_Store"} == expected
record = {"destination": str(destination), "history": str(history), "screenshots": 24, "previews": 8,
          "creativeAssets": creative_count,
          "files": [{"path": str(relative), "sha256": sha} for _, relative, sha in files]}
(media / "final-delivery.json").write_text(json.dumps(record, indent=2) + "\n")
print(destination)
print(f"Copied and verified 24 screenshots, 8 previews and {creative_count} approved creative assets.")
