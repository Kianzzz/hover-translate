#!/usr/bin/env python3
"""Check real Vision OCR with synthetic text only; no screen permission needed."""
import json
from pathlib import Path
import subprocess
import sys

binary = sys.argv[1]
fixture = Path(__file__).resolve().parent.parent / "Tests/Fixtures/ocr-context.png"
cases = [
    (180, 142, "This is a long sentence that continues on the next line and needs context to translate correctly."),
    (420, 172, "Another sentence."),
    (240, 242, "A separate paragraph should stay separate."),
    (150, 352, "Keep in Dock"),
    (700, 500, None),
]
for x, y, expected in cases:
    completed = subprocess.run([binary, "--check-image", str(fixture), str(x), str(y)],
                               text=True, capture_output=True, timeout=30, check=True)
    found = json.loads(completed.stdout)["text"]
    if found != expected:
        raise SystemExit(f"OCR CHECK FAILED at ({x}, {y}): expected {expected!r}, got {found!r}")
    print(f"PASS: {found or 'blank space skipped'}", flush=True)
print("5 real OCR context checks passed.")
