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
        "solo_fixture_result", "solo_fixture_stage", "solo_apply_fixture_stage",
        "solo_new_game_fixture_stage", "solo_action_count",
        "solo_rng_fixture_stage",
        "solo_complete_remaining", "solo_complete_pages",
        "solo_complete_games_passed", "solo_complete_games_bounded",
        "solo_complete_failure",
        "solo_action_kind", "solo_action_rank", "solo_action_suit_mask",
        "solo_action_nomination", "solo_group_mask", "solo_valid_mask",
        "solo_scan_rank", "solo_debug_hand0", "solo_debug_hand1",
        "solo_debug_hand4", "solo_debug_hand5", "solo_debug_top",
        "solo_debug_deck0", "solo_debug_seed",
    ]
    addresses = {}
    for name in names:
        match = re.search(rf"^al ([0-9A-Fa-f]+) \.{name}$", labels, re.MULTILINE)
        if not match:
            raise SystemExit(f"{name} missing from label file")
        addresses[name] = int(match.group(1), 16)
    address = addresses["solo_fixture_result"]
    # Direct-SYS the machine-code portion, entering at a fixed address rather
    # than through BASIC's RUN, so the frame budget below measures the kernel
    # and not the editor.
    linked = (ROOT / "build/rachel-solo-kernel-spike.prg").read_bytes()
    sys_prg = ROOT / "build/rachel-solo-kernel-spike-sys.prg"
    sys_prg.write_bytes(bytes((0x10, 0x12)) + linked[17:])
    session = ROOT / "build/solo-kernel-e2e.json"
    session.write_text(json.dumps([
        # The fixture now includes a complete deterministic match in addition
        # to the focused kernel cases.
        {"action": "run_frames", "frames": 70000},
        *(
            {
                "action": "memory_read", "addr": item,
                "len": 1,
            }
            for name, item in addresses.items()
        ),
    ], indent=2) + "\n")
    result = subprocess.run([
        str(BIN), "--headless", "--ram-expansion", "8k",
        "--prg", str(sys_prg), "--prg-sys",
        "--script", str(session),
    ], cwd=EMU, check=True, text=True, capture_output=True)
    report = json.loads(result.stdout)
    reads = [item for item in report["observations"] if item["kind"] == "memory_read"]
    debug = dict(zip(addresses, (item["bytes"] for item in reads)))
    if (len(reads) != len(addresses) or reads[0]["bytes"] != [0xA5]
            or debug["solo_complete_games_passed"] != [16]
            or debug["solo_complete_failure"] != [0]):
        raise SystemExit(f"solo fixture validation failed: {debug}")
    bounded = debug["solo_complete_games_bounded"][0]
    print(f"Executable compact solo fixture passed at ${address:04X}; "
          f"16 seeds exercised, {bounded} reached the 1024-turn bound")


if __name__ == "__main__":
    main()
