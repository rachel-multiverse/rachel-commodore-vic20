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
    names = [
        "solo_fixture_result", "solo_fixture_stage", "solo_action_count",
        "solo_action_kind", "solo_action_rank", "solo_action_suit_mask",
        "solo_action_nomination", "solo_group_mask", "solo_valid_mask",
        "solo_scan_rank",
    ]
    addresses = {}
    for name in names:
        match = re.search(rf"^al ([0-9A-Fa-f]+) \.{name}$", labels, re.MULTILINE)
        if not match:
            raise SystemExit(f"{name} missing from label file")
        addresses[name] = int(match.group(1), 16)
    address = addresses["solo_fixture_result"]
    session = ROOT / "build/solo-kernel-e2e.json"
    session.write_text(json.dumps([
        {"action": "run_frames", "frames": 4000},
        *(
            {"action": "memory_read", "addr": item, "len": 1}
            for item in addresses.values()
        ),
    ], indent=2) + "\n")
    result = subprocess.run([
        str(BIN), "--headless", "--ram-expansion-kb", "8",
        "--prg", str(ROOT / "build/rachel-solo-kernel-spike.prg"),
        "--script", str(session),
    ], cwd=EMU, check=True, text=True, capture_output=True)
    report = json.loads(result.stdout)
    reads = [item for item in report["observations"] if item["kind"] == "memory_read"]
    if len(reads) != len(addresses) or reads[0]["bytes"] != [0xA5]:
        debug = dict(zip(addresses, (item["bytes"][0] for item in reads)))
        raise SystemExit(f"solo fixture validation failed: {debug}")
    print(f"Executable compact solo fixture passed at ${address:04X}")


if __name__ == "__main__":
    main()
