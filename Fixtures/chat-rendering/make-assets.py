#!/usr/bin/env python3
"""Writes the binary files the chat rendering fixture attaches.

The files are checked in, so nothing has to run this to use the fixture. Run
it again only to change one: every file is drawn from fixed values, so the
same script writes the same bytes. Needs Pillow, ffmpeg and zip.
"""

import os
import subprocess
import zipfile

from PIL import Image, ImageDraw

DIRECTORY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets")


def draw_picture(path, width, height, colors, label):
    picture = Image.new("RGB", (width, height), colors[0])
    pen = ImageDraw.Draw(picture)
    stripe = max(width, height) // 8
    for index in range(0, width + height, stripe):
        pen.line([(index, 0), (index - height, height)], fill=colors[1], width=stripe // 3)
    pen.rectangle([width // 10, height // 10, width - width // 10, height - height // 10], outline=colors[2], width=6)
    pen.text((width // 8, height // 8), label, fill=colors[2])
    picture.save(path, optimize=True)


def main():
    os.makedirs(DIRECTORY, exist_ok=True)
    draw_picture(os.path.join(DIRECTORY, "photo-landscape.png"), 960, 540, ("#2f4858", "#33658a", "#f6ae2d"), "Landscape 960 x 540")
    draw_picture(os.path.join(DIRECTORY, "photo-portrait.png"), 480, 840, ("#3d405b", "#81b29a", "#f2cc8f"), "Portrait 480 x 840")
    draw_picture(os.path.join(DIRECTORY, "photo-square.png"), 400, 400, ("#264653", "#2a9d8f", "#e9c46a"), "Square 400")
    draw_picture(os.path.join(DIRECTORY, "preview-card.png"), 1200, 630, ("#1d3557", "#457b9d", "#f1faee"), "Preview picture 1200 x 630")

    # A two second test pattern with a tone, small enough to check in.
    subprocess.run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=15:duration=2",
        "-f", "lavfi", "-i", "sine=frequency=440:duration=2",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-profile:v", "baseline", "-crf", "36",
        "-c:a", "aac", "-b:a", "32k", "-shortest", "-movflags", "+faststart",
        "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:v", "+bitexact", "-flags:a", "+bitexact",
        os.path.join(DIRECTORY, "clip.mp4"),
    ], check=True)
    # A voice message: four seconds of a soft rising tone.
    subprocess.run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "lavfi", "-i", "sine=frequency=220:duration=4",
        "-af", "volume=0.3", "-c:a", "libopus", "-b:a", "16k",
        "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact",
        os.path.join(DIRECTORY, "voice.webm"),
    ], check=True)

    with open(os.path.join(DIRECTORY, "shift-summary.csv"), "w", newline="") as output:
        output.write("shift,picks,faults,uptime_percent\n")
        for row in (("morning", 1840, 3, 97.2), ("afternoon", 1712, 5, 95.8), ("night", 1530, 1, 98.6)):
            output.write(",".join(str(value) for value in row) + "\n")

    with open(os.path.join(DIRECTORY, "maintenance-checklist.pdf"), "wb") as output:
        output.write(minimal_pdf("Maintenance checklist: inspect the gripper pads and the belt."))

    archive_path = os.path.join(DIRECTORY, "debug-logs.zip")
    with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED) as archive:
        info = zipfile.ZipInfo("logs/planner.log", date_time=(2026, 1, 1, 0, 0, 0))
        archive.writestr(info, "planner started\nplan found in 41 ms\n")

    with open(os.path.join(DIRECTORY, "a-very-long-file-name-that-keeps-going-to-check-wrapping-and-ellipsis-in-the-card.txt"), "w") as output:
        output.write("A file whose name is longer than any card is wide.\n")

    with open(os.path.join(DIRECTORY, "weekly-report.md"), "w") as output:
        output.write(WEEKLY_REPORT)
    with open(os.path.join(DIRECTORY, "throughput-page.html"), "w") as output:
        output.write(THROUGHPUT_PAGE)


def minimal_pdf(text):
    stream = f"BT /F1 14 Tf 40 760 Td ({text}) Tj ET".encode()
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
        b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n" + stream + b"\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    body = b"%PDF-1.4\n"
    offsets = []
    for number, content in enumerate(objects, start=1):
        offsets.append(len(body))
        body += f"{number} 0 obj\n".encode() + content + b"\nendobj\n"
    table = len(body)
    body += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode()
    for offset in offsets:
        body += f"{offset:010d} 00000 n \n".encode()
    body += f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{table}\n%%EOF\n".encode()
    return body


WEEKLY_REPORT = """# Weekly line report

A short document artifact, to check how a markdown artifact reads in its card
and at full size.

## Summary

| Day | Picks | Faults |
|-----|------:|-------:|
| Monday | 1,840 | 3 |
| Tuesday | 1,712 | 5 |
| Wednesday | 1,955 | 2 |

- Uptime held above 95 percent every day.
- Two faults were the same gripper pad.

```mermaid
flowchart LR
  Inspect --> Replace --> Verify
```

The pick rate is $r = \\frac{n}{t}$ picks per hour.
"""

THROUGHPUT_PAGE = """<!doctype html>
<html><head><meta charset="utf-8"><title>Throughput</title></head>
<body>
<h1>Throughput by hour</h1>
<p>A small page artifact with a chart drawn in SVG.</p>
<svg viewBox="0 0 320 160" width="320" height="160" role="img" aria-label="Bars">
  <rect x="20" y="60" width="40" height="90" fill="#3b82f6"/>
  <rect x="80" y="30" width="40" height="120" fill="#3b82f6"/>
  <rect x="140" y="80" width="40" height="70" fill="#3b82f6"/>
  <rect x="200" y="20" width="40" height="130" fill="#3b82f6"/>
  <rect x="260" y="50" width="40" height="100" fill="#3b82f6"/>
</svg>
</body></html>
"""


if __name__ == "__main__":
    main()
