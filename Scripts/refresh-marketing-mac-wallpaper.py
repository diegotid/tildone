#!/usr/bin/env python3
"""Prepare and resume a native Mac-only wallpaper refresh without replacing finals."""
import argparse
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
OUTPUT = REPO / "Marketing/Preview/Output"
LOCALES = ["en-US", "es-ES", "fr-FR", "zh-Hans"]
STORIES = [f"screenshot-{n}" for n in range(1, 7)] + ["desktop", "sync"]
BUNDLE = "studio.cuatro.tildone.marketing-preview"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--phase", choices=["prepare", "capture", "export", "audit"], required=True)
    parser.add_argument("--app-template", type=Path)
    parser.add_argument("--wallpaper", type=Path)
    parser.add_argument("--stories", choices=STORIES, nargs="+", default=STORIES)
    parser.add_argument("--locales", choices=LOCALES, nargs="+", default=LOCALES)
    args = parser.parse_args()
    root = args.output.resolve()
    assert root.is_relative_to(OUTPUT) and root != OUTPUT
    plan_path = root / "mac-capture-plan.json"
    if args.phase == "prepare":
        assert args.app_template and args.wallpaper and not plan_path.exists()
        template = args.app_template.resolve(strict=True)
        info = plistlib.loads((template / "Contents/Info.plist").read_bytes())
        assert info["CFBundleIdentifier"] == BUNDLE
        wallpaper = args.wallpaper.resolve(strict=True)
        jobs = []
        for story in STORIES:
            for locale in LOCALES:
                directory = root / "native" / story / locale
                app = directory / "TildonePreviewStudio.app"
                shutil.copytree(template, app)
                configured = dict(info, MarketingStory=story, MarketingLocale=locale,
                                  MarketingOutputDirectory=str(directory))
                if story in ["sync", "screenshot-2"]:
                    # Reuse the unchanged verified phone fixtures. Mac-only
                    # refreshes must not replace any iPhone media or prerequisite.
                    existing = (OUTPUT / "sync/revision-7" / locale if story == "sync" else
                                OUTPUT / "screenshots/02" / locale)
                    phone = directory / "TildonePhonePreview.app"
                    shutil.copytree(existing / "TildonePhonePreview.app", phone)
                    phone_info = plistlib.loads((phone / "Info.plist").read_bytes())
                    assert phone_info["CFBundleIdentifier"] == "studio.cuatro.tildone.marketing-phone"
                    assert phone_info["MarketingLocale"] == locale
                    frames = directory / "phone-frames"
                    shutil.copytree(existing / "phone-frames", frames)
                    assert (frames / "phone-capture-verification.json").is_file()
                    save(directory / "retained-phone-inputs.json", {
                        "story": story, "locale": locale, "framesDirectory": str(frames),
                        "sourceFramesDirectory": str(existing / "phone-frames"),
                        "files": {str(f.relative_to(frames)): digest(f)
                                  for f in frames.rglob("*") if f.is_file() and f.name != ".DS_Store"}})
                    configured.update(MarketingPhoneCaptureAppDirectory=str(phone),
                                      MarketingPhoneFramesDirectory=str(frames))
                (app / "Contents/Info.plist").write_bytes(plistlib.dumps(configured))
                shutil.copy2(wallpaper, app / "Contents/Resources/GoldenGate.png")
                save(directory / "input-manifest.json", {
                    "story": story, "locale": locale, "bundleIdentifier": BUNDLE,
                    "wallpaperSHA256": digest(wallpaper),
                    "executableSHA256": digest(app / "Contents/MacOS/Tildone"),
                    "mockDataOnly": True, "customerAppLaunched": False})
                (directory / "capture-status.txt").write_text("BUILT")
                jobs.append({"story": story, "locale": locale, "app": str(app),
                             "directory": str(directory)})
        save(plan_path, {"scope": "Mac screenshots and previews only", "jobs": jobs,
                         "wallpaper": str(wallpaper), "wallpaperSHA256": digest(wallpaper),
                         "destination": str(root / "ready-for-review")})
        print(f"Prepared {len(jobs)} isolated native Mac captures. No capture started.", flush=True)
        return

    plan = json.loads(plan_path.read_text())
    destination = Path(plan["destination"])
    destination.mkdir(exist_ok=True)
    environment = dict(os.environ)
    environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + environment.get("PATH", "")
    jobs = [job for job in plan["jobs"] if job["story"] in args.stories and job["locale"] in args.locales]
    first_capture = True
    for number, job in enumerate(jobs, 1):
        directory, app = Path(job["directory"]), Path(job["app"])
        assert digest(app / "Contents/Resources/GoldenGate.png") == plan["wallpaperSHA256"]
        story, locale = job["story"], job["locale"]
        print(f"{args.phase} {number}/{len(jobs)}: {story} {locale}", flush=True)
        if args.phase == "capture":
            done = directory / "wallpaper-capture-complete.json"
            if done.exists():
                assert json.loads(done.read_text())["wallpaperSHA256"] == plan["wallpaperSHA256"]
                continue
            command = [sys.executable, str(REPO / "Scripts/record-marketing-preview.py"),
                       "--app", str(app), "--batch", "--destination", str(destination),
                       "--countdown", "10" if first_capture else "0"]
            if story in ["sync", "screenshot-2"]:
                command += ["--retained-phone-inputs", str(directory / "retained-phone-inputs.json")]
            with (directory / "capture-launcher.log").open("w") as log:
                subprocess.run(command, cwd=REPO, env=environment, check=True,
                               stdout=log, stderr=subprocess.STDOUT, timeout=200)
            first_capture = False
            save(done, {"wallpaperSHA256": plan["wallpaperSHA256"], "nativeCapture": True})
        elif args.phase == "export" and story in ["desktop", "sync"]:
            with (directory / "export-launcher.log").open("w") as log:
                subprocess.run([sys.executable, str(REPO / "Scripts/export-marketing-preview.py"),
                                "--output", str(directory)], cwd=REPO, env=environment,
                               stdout=log, stderr=subprocess.STDOUT, check=True, timeout=240)
            name = f"Tildone-macOS-preview{'-2-sync' if story == 'sync' else ''}-{locale}.mp4"
            shutil.copy2(directory / name, destination / name)
        elif args.phase == "audit":
            result_path = directory / ("screenshot-result.json" if story.startswith("screenshot-") else "capture-result.json")
            proof = json.loads(result_path.read_text())
            assert proof["mockDataOnly"] and not proof["cloudKitStarted"]
            assert proof.get("locale", "en-US") == locale
            if story.startswith("screenshot-"):
                name = f"Tildone-macOS-screenshot-{int(story.rsplit('-', 1)[1]):02}-{locale}.png"
            else:
                name = f"Tildone-macOS-preview{'-2-sync' if story == 'sync' else ''}-{locale}.mp4"
                assert (directory / "export-verification.json").is_file()
            assert digest(directory / name) == digest(destination / name)
        save(root / "mac-refresh-status.json", {"phase": args.phase, "completed": number,
             "total": len(jobs), "story": story, "locale": locale})
    if args.phase == "capture":
        if len(jobs) == len(plan["jobs"]):
            print("NATIVE CAPTURES FINISHED. You can use other apps again.", flush=True)
        else:
            print("Selected native capture phase finished.", flush=True)
    elif args.phase == "audit":
        media = sorted(destination.glob("*.png")) + sorted(destination.glob("*.mp4"))
        save(root / "mac-refresh-export-manifest.json", {
            "scope": plan["scope"], "wallpaperSHA256": plan["wallpaperSHA256"],
            "screenshots": len(list(destination.glob("*.png"))),
            "previews": len(list(destination.glob("*.mp4"))),
            "files": [{"file": f.name, "sha256": digest(f), "bytes": f.stat().st_size} for f in media],
            "visualReviewPending": True, "publishedToAppStoreConnect": False})
        print("Native proof and export fingerprints verified; visual review remains.", flush=True)


if __name__ == "__main__":
    main()
