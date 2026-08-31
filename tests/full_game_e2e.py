#!/usr/bin/env python3
"""Complete a deterministic VIC-20 game in Emu198x against the Go server."""

from pathlib import Path
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
SERVER = Path(os.environ.get("RACHEL_SERVER_DIR", ROOT.parent / "rachel-server"))
EMU = Path(os.environ.get("EMU198X_DIR", ""))
EMU_BIN = EMU / "target/release/emu198x-commodore-vic-20"
OUTPUT = ROOT / "build/e2e-output"
SEED = int(os.environ.get("RACHEL_E2E_SEED", "2"))


def require_environment() -> None:
    missing = []
    if not SERVER.joinpath("go.mod").is_file():
        missing.append("RACHEL_SERVER_DIR")
    if not EMU_BIN.is_file():
        missing.append("EMU198X_DIR (with a release VIC-20 runner)")
    if missing:
        raise SystemExit("missing " + ", ".join(missing))


def wait_for_server(process: subprocess.Popen[str]) -> None:
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError("Rachel server exited before listening")
        try:
            with socket.create_connection(("127.0.0.1", 6502), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    raise RuntimeError("Rachel server did not listen on port 6502")


def stop_group(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()


def main() -> None:
    require_environment()
    subprocess.run(["make", "e2e-prg"], cwd=ROOT, check=True)
    shutil.rmtree(OUTPUT, ignore_errors=True)
    OUTPUT.mkdir(parents=True)
    session_path = OUTPUT / "session.json"
    screenshot_path = OUTPUT / "final.png"
    server_log_path = OUTPUT / "server.log"
    emulator_log_path = OUTPUT / "emulator.json"
    session_path.write_text(json.dumps([
        {"action": "run_frames", "frames": 220},
        {"action": "press_key", "key": "Space", "hold_frames": 3},
        {"action": "type_string", "text": "127.0.0.1\n", "hold_frames": 2,
         "settle_frames": 20},
        {"action": "run_frames", "frames": 30000},
    ], indent=2) + "\n")

    command = ["go", "run", ".", "serve", "--addr", "127.0.0.1:6502",
               "--min-players", "2", "--ai-players", "1", "--auto-start", "1ms",
               "--ai-delay", "0", "--random-seed", str(SEED),
               "--vic20-write-interval", "70ms"]
    with server_log_path.open("w+") as server_log:
        server = subprocess.Popen(command, cwd=SERVER, stdout=server_log,
                                  stderr=subprocess.STDOUT, text=True,
                                  start_new_session=True)
        try:
            wait_for_server(server)
            result = subprocess.run([
                str(EMU_BIN), "--headless", "--ram-expansion-kb", "8",
                "--prg", str(ROOT / "build/rachel-e2e.prg"), "--esp-at-tcp",
                "--script", str(session_path), "--screenshot", str(screenshot_path),
            ], cwd=EMU, text=True, capture_output=True, timeout=180)
            emulator_log_path.write_text(result.stdout + result.stderr)
        finally:
            stop_group(server)

    server_text = server_log_path.read_text()
    if result.returncode:
        raise SystemExit(f"emulator failed; see {emulator_log_path}")
    if "Game finished" not in server_text:
        raise SystemExit(f"game did not finish; see {server_log_path}")
    if "Client error" in server_text:
        raise SystemExit(f"server rejected a client action; see {server_log_path}")
    if not screenshot_path.is_file():
        raise SystemExit("emulator did not produce the final screenshot")
    if screenshot_path.stat().st_size < 1_000:
        raise SystemExit("final screenshot is unexpectedly blank or truncated")
    print(f"Complete deterministic VIC-20 game passed: {OUTPUT}")


if __name__ == "__main__":
    try:
        main()
    except subprocess.TimeoutExpired as error:
        print(f"timed out: {error}", file=sys.stderr)
        raise SystemExit(1)
