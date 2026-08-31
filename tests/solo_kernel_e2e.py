#!/usr/bin/env python3
"""Execute the compact workspace loader and inspect its result in Emu198x."""

from pathlib import Path
import json
import os
import re
import subprocess


ROOT = Path(__file__).resolve().parents[1]
EMU = Path(os.environ.get("EMU198X_DIR", ""))
BIN = EMU / "target/release/emu198x-commodore-vic-20"


def main() -> None:
    if not BIN.is_file():
        raise SystemExit("missing EMU198X_DIR with a release VIC-20 runner")
    labels = (ROOT / "build/solo-kernel-spike.lbl").read_text()
    match = re.search(r"^al ([0-9A-Fa-f]+) \.solo_fixture_result$", labels, re.MULTILINE)
    if not match:
        raise SystemExit("solo_fixture_result missing from label file")
    address = int(match.group(1), 16)
    session = ROOT / "build/solo-kernel-e2e.json"
    session.write_text(json.dumps([
        {"action": "run_frames", "frames": 220},
        {"action": "memory_read", "addr": address, "len": 1},
    ], indent=2) + "\n")
    result = subprocess.run([
        str(BIN), "--headless", "--ram-expansion-kb", "8",
        "--prg", str(ROOT / "build/rachel-solo-kernel-spike.prg"),
        "--script", str(session),
    ], cwd=EMU, check=True, text=True, capture_output=True)
    report = json.loads(result.stdout)
    reads = [item for item in report["observations"] if item["kind"] == "memory_read"]
    if len(reads) != 1 or reads[0]["bytes"] != [0xA5]:
        raise SystemExit(f"solo fixture validation failed: {reads}")
    print(f"Executable compact solo fixture passed at ${address:04X}")


if __name__ == "__main__":
    main()
