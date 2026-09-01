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
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
SERVER = Path(os.environ.get("RACHEL_SERVER_DIR", ROOT.parent / "rachel-server"))
EMU = Path(os.environ.get("EMU198X_DIR", ""))
EMU_BIN = EMU / "target/release/emu198x-commodore-vic-20"
OUTPUT = ROOT / "build" / os.environ.get("RACHEL_E2E_OUTPUT", "e2e-output")
SEED = int(os.environ.get("RACHEL_E2E_SEED", "2"))
MIN_PLAYERS = int(os.environ.get("RACHEL_E2E_MIN_PLAYERS", "2"))
AI_PLAYERS = int(os.environ.get("RACHEL_E2E_AI_PLAYERS", "1"))
GAME_FRAMES = int(os.environ.get("RACHEL_E2E_GAME_FRAMES", "120000"))
DROP_AFTER = int(os.environ.get("RACHEL_E2E_DROP_AFTER_SERVER_FRAMES", "0"))
WRITE_INTERVAL = os.environ.get("RACHEL_E2E_WRITE_INTERVAL", "300ms")
REGION = os.environ.get("RACHEL_E2E_REGION", "pal").lower()


class DropOnceProxy:
    """TCP relay that drops the first game link after N server frames."""

    def __init__(self, drop_after: int) -> None:
        self.drop_after = drop_after
        self.stop_event = threading.Event()
        self.dropped = threading.Event()
        self.error: Exception | None = None
        self.listener: socket.socket | None = None
        self.thread = threading.Thread(target=self.run, daemon=True)

    def start(self) -> None:
        self.thread.start()
        deadline = time.monotonic() + 5
        while self.listener is None and self.error is None and time.monotonic() < deadline:
            time.sleep(0.01)
        if self.error:
            raise self.error
        if self.listener is None:
            raise RuntimeError("reconnect proxy did not start")

    def stop(self) -> None:
        self.stop_event.set()
        if self.listener:
            self.listener.close()
        self.thread.join(timeout=5)

    def run(self) -> None:
        try:
            with socket.socket() as listener:
                listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                listener.bind(("127.0.0.1", 6502))
                listener.listen()
                listener.settimeout(0.2)
                self.listener = listener
                while not self.stop_event.is_set():
                    try:
                        client, _ = listener.accept()
                    except socket.timeout:
                        continue
                    with client, socket.create_connection(("127.0.0.1", 6503)) as upstream:
                        client.settimeout(0.05)
                        upstream.settimeout(0.05)
                        server_bytes = 0
                        while not self.stop_event.is_set():
                            progressed = False
                            for source, destination, from_server in (
                                (client, upstream, False), (upstream, client, True),
                            ):
                                try:
                                    data = source.recv(4096)
                                except socket.timeout:
                                    continue
                                except OSError:
                                    data = b""
                                if not data:
                                    break
                                try:
                                    destination.sendall(data)
                                except OSError:
                                    break
                                progressed = True
                                if from_server and not self.dropped.is_set():
                                    server_bytes += len(data)
                                    if server_bytes >= self.drop_after * 64:
                                        self.dropped.set()
                                        break
                            else:
                                if progressed or not self.stop_event.is_set():
                                    continue
                            break
        except OSError as error:
            if not self.stop_event.is_set():
                self.error = error


def require_environment() -> None:
    missing = []
    if not SERVER.joinpath("go.mod").is_file():
        missing.append("RACHEL_SERVER_DIR")
    if not EMU_BIN.is_file():
        missing.append("EMU198X_DIR (with a release VIC-20 runner)")
    if missing:
        raise SystemExit("missing " + ", ".join(missing))
    if REGION not in {"pal", "ntsc"}:
        raise SystemExit("RACHEL_E2E_REGION must be pal or ntsc")


def wait_for_server(process: subprocess.Popen[str], port: int = 6502) -> None:
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError("Rachel server exited before listening")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
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
    linked = (ROOT / "build/rachel-e2e.prg").read_bytes()
    sys_prg = ROOT / "build/rachel-e2e-sys.prg"
    sys_prg.write_bytes(bytes((0x10, 0x12)) + linked[17:])
    shutil.rmtree(OUTPUT, ignore_errors=True)
    OUTPUT.mkdir(parents=True)
    session_path = OUTPUT / "session.json"
    screenshot_path = OUTPUT / "final.png"
    server_log_path = OUTPUT / "server.log"
    emulator_log_path = OUTPUT / "emulator.json"
    session_path.write_text(json.dumps([
        {"action": "run_frames", "frames": 220},
        {"action": "press_key", "key": "O", "hold_frames": 3},
        {"action": "type_string", "text": "127.0.0.1\n\n", "hold_frames": 2,
         "settle_frames": 20},
        {"action": "run_frames", "frames": GAME_FRAMES},
    ], indent=2) + "\n")

    server_port = 6503 if DROP_AFTER else 6502
    command = ["go", "run", ".", "serve", "--addr", f"127.0.0.1:{server_port}",
               "--min-players", str(MIN_PLAYERS), "--ai-players", str(AI_PLAYERS),
               "--auto-start", "1ms",
               "--ai-delay", "0", "--random-seed", str(SEED),
               "--vic20-write-interval", WRITE_INTERVAL]
    with server_log_path.open("w+") as server_log:
        proxy = DropOnceProxy(DROP_AFTER) if DROP_AFTER else None
        server = subprocess.Popen(command, cwd=SERVER, stdout=server_log,
                                  stderr=subprocess.STDOUT, text=True,
                                  start_new_session=True)
        try:
            wait_for_server(server, server_port)
            if proxy:
                proxy.start()
            result = subprocess.run([
                str(EMU_BIN), "--headless", "--region", REGION,
                "--ram-expansion", "8k",
                "--prg", str(sys_prg), "--prg-sys", "--esp-at-tcp",
                "--script", str(session_path), "--screenshot", str(screenshot_path),
            ], cwd=EMU, text=True, capture_output=True, timeout=360)
            emulator_log_path.write_text(result.stdout + result.stderr)
        finally:
            if proxy:
                proxy.stop()
            stop_group(server)

    server_text = server_log_path.read_text()
    if result.returncode:
        raise SystemExit(f"emulator failed; see {emulator_log_path}")
    if "Game finished" not in server_text:
        raise SystemExit(f"game did not finish; see {server_log_path}")
    if "Client error" in server_text:
        raise SystemExit(f"server rejected a client action; see {server_log_path}")
    if proxy and (not proxy.dropped.is_set() or proxy.error):
        raise SystemExit(f"TCP fault injection failed: {proxy.error}")
    if DROP_AFTER and "reclaimed player" not in server_text:
        raise SystemExit(f"client did not reclaim its seat; see {server_log_path}")
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
