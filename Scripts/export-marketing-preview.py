#!/usr/bin/env python3
"""Conform and inspect the isolated app's recording; requires ffmpeg/ffprobe."""
import argparse
import json
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path, default=Path("Marketing/Preview/Output"))
args = parser.parse_args()
output = args.output.resolve()
result = json.loads((output / "capture-result.json").read_text())
assert result["status"] == "complete"
assert result["mockDataOnly"] and not result["cloudKitStarted"]
assert result["notesRemaining"] == 2 and result["capturedTaskPresent"], result
if "backgroundDocument" in result:
    assert result["backgroundDocumentActivated"] and result["pendingNotesAboveBackground"], result
    completed, home, weekend = result["openingWindowSizes"]
    for dimension in ("width", "height"):
        assert abs(completed[dimension] / weekend[dimension] - 1.15) < 0.01, result
        assert abs(home[dimension] / weekend[dimension] - 0.85) < 0.01, result
    if result["backgroundDocument"] == "native-mock-email-inbox":
        if result.get("compositionRevision", 4) >= 5:
            assert abs(result["backgroundWindowSize"]["width"] - 390 * 1.25) <= 1, result
            assert abs(result["backgroundWindowSize"]["height"] - 308 * 1.25) <= 1, result
            today_origin, home_origin, weekend_origin = result["openingWindowOrigins"]
            # Native child-window coordinates round with the canvas origin.
            # Compare with unchanged Today and the measured Home horizontal position.
            assert abs(result["backgroundWindowOrigin"]["x"] - (home_origin["x"] + home["width"] / 2 + 195)) <= 1, result
            assert abs(home_origin["y"] - (today_origin["y"] + (215 - 270) * 0.75 - home["height"] * 0.25)) <= 1, result
            assert abs(weekend_origin["y"] - (today_origin["y"] - weekend["height"] * 0.25)) <= 1, result
            assert result["backgroundWindowTitle"] == "Mail", result
        else:
            assert abs(result["backgroundWindowSize"]["width"] - 390) <= 1, result
            assert abs(result["backgroundWindowSize"]["height"] - 362 * 0.85) <= 1, result
            assert abs(result["blueNoteOverlapFraction"] - 0.5) < 0.01, result
raw = output / "Tildone-macOS-preview-raw.mp4"
final = output / "Tildone-macOS-preview-en-US.mp4"
command = [
    "ffmpeg", "-hide_banner", "-y", "-i", str(raw),
    "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000",
    "-map", "0:v:0", "-map", "1:a:0", "-t", "30",
    "-vf", "fps=30,scale=1920:1080:flags=lanczos,format=yuv420p",
    "-c:v", "libx264", "-preset", "slow", "-profile:v", "high", "-level:v", "4.0",
    "-b:v", "11M", "-maxrate", "12M", "-bufsize", "24M",
    "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709",
    "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2",
    "-movflags", "+faststart", str(final),
]
with (output / "export.log").open("w") as log:
    subprocess.run(command, check=True, stdout=log, stderr=subprocess.STDOUT)
probe = json.loads(subprocess.check_output([
    "ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(final)
]))
video = next(s for s in probe["streams"] if s["codec_type"] == "video")
audio = next(s for s in probe["streams"] if s["codec_type"] == "audio")
assert (video["width"], video["height"], video["codec_name"], video["pix_fmt"], video["r_frame_rate"], int(video["nb_frames"])) == (1920, 1080, "h264", "yuv420p", "30/1", 900)
assert audio["codec_name"] == "aac" and audio["channels"] == 2 and audio["sample_rate"] == "48000"
assert abs(float(probe["format"]["duration"]) - 30) < 0.05
(output / "export-verification.json").write_text(json.dumps(probe, indent=2) + "\n")
for second in [2, 6, 10, 15, 22, 28]:
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-ss", str(second),
                    "-i", str(final), "-frames:v", "1", str(output / f"frame-{second:02}.png")], check=True)
subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(final),
                "-vf", "fps=1/5,scale=640:-1,tile=3x2", "-frames:v", "1",
                str(output / "contact-sheet.png")], check=True)
print(final)
print("Verified: exactly 30 seconds, 900 frames, 1920x1080 H.264, stereo AAC, and mock interactions.")
