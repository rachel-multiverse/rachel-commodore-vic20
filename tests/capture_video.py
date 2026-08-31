#!/usr/bin/env python3
"""Capture a deterministic Rachel/VIC-20 match as an authentic emulator video."""

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
OUTPUT = Path(os.environ.get("RACHEL_CAPTURE_DIR", ROOT / "build/video-capture"))
SEED = int(os.environ.get("RACHEL_E2E_SEED", "2"))
CAPTURE_EVERY = int(os.environ.get("RACHEL_CAPTURE_EVERY", "100"))
GAME_FRAMES = int(os.environ.get("RACHEL_CAPTURE_GAME_FRAMES", "30000"))
VIDEO_FPS = int(os.environ.get("RACHEL_CAPTURE_FPS", "8"))
SCALE = int(os.environ.get("RACHEL_CAPTURE_SCALE", "4"))


def require_environment() -> None:
    missing = []
    if not SERVER.joinpath("go.mod").is_file():
        missing.append("RACHEL_SERVER_DIR")
    if not EMU_BIN.is_file():
        missing.append("EMU198X_DIR (with a release VIC-20 runner)")
    if not shutil.which("ffmpeg"):
        missing.append("ffmpeg")
    if missing:
        raise SystemExit("missing " + ", ".join(missing))
    if min(CAPTURE_EVERY, GAME_FRAMES, VIDEO_FPS, SCALE) < 1:
        raise SystemExit("capture frame, rate and scale settings must be positive")


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


def screenshot(steps: list[dict[str, object]], frames: Path, index: int) -> int:
    steps.append({"action": "save_screenshot", "path": str(frames / f"frame-{index:05d}.png")})
    return index + 1


def make_session(frames: Path) -> tuple[list[dict[str, object]], int]:
    steps: list[dict[str, object]] = [{"action": "run_frames", "frames": 220}]
    index = 0
    # Give the title enough screen time to be readable in the encoded video.
    for _ in range(VIDEO_FPS * 2):
        index = screenshot(steps, frames, index)
    steps.extend([
        {"action": "press_key", "key": "O", "hold_frames": 3},
        {"action": "run_frames", "frames": 20},
    ])
    for _ in range(VIDEO_FPS):
        index = screenshot(steps, frames, index)
    steps.append({"action": "type_string", "text": "127.0.0.1\n\n", "hold_frames": 2,
                  "settle_frames": 20})
    remaining = GAME_FRAMES
    while remaining:
        advance = min(CAPTURE_EVERY, remaining)
        steps.append({"action": "run_frames", "frames": advance})
        index = screenshot(steps, frames, index)
        remaining -= advance
    # Hold the terminal result rather than ending on a single fleeting frame.
    for _ in range(VIDEO_FPS * 3):
        index = screenshot(steps, frames, index)
    return steps, index


def encode_video(frames: Path, video: Path) -> None:
    subprocess.run([
        "ffmpeg", "-hide_banner", "-loglevel", "warning", "-y",
        "-framerate", str(VIDEO_FPS), "-i", str(frames / "frame-%05d.png"),
        "-vf", f"scale=iw*{SCALE}:ih*{SCALE}:flags=neighbor",
        "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p",
        "-movflags", "+faststart", str(video),
    ], check=True)


def main() -> None:
    require_environment()
    subprocess.run(["make", "e2e-prg"], cwd=ROOT, check=True)
    linked = (ROOT / "build/rachel-e2e.prg").read_bytes()
    sys_prg = ROOT / "build/rachel-e2e-sys.prg"
    sys_prg.write_bytes(bytes((0x10, 0x12)) + linked[17:])
    shutil.rmtree(OUTPUT, ignore_errors=True)
    frames = OUTPUT / "frames"
    frames.mkdir(parents=True)
    session_path = OUTPUT / "session.json"
    server_log_path = OUTPUT / "server.log"
    emulator_log_path = OUTPUT / "emulator.json"
    video_path = OUTPUT / "rachel-vic20.mp4"
    poster_path = OUTPUT / "poster.png"
    steps, expected_frames = make_session(frames)
    session_path.write_text(json.dumps(steps, indent=2) + "\n")

    command = ["go", "run", ".", "serve", "--addr", "127.0.0.1:6502",
               "--min-players", "2", "--ai-players", "1", "--auto-start", "1ms",
               "--ai-delay", "0", "--random-seed", str(SEED),
               "--vic20-write-interval", "100ms"]
    with server_log_path.open("w+") as server_log:
        server = subprocess.Popen(command, cwd=SERVER, stdout=server_log,
                                  stderr=subprocess.STDOUT, text=True,
                                  start_new_session=True)
        try:
            wait_for_server(server)
            result = subprocess.run([
                str(EMU_BIN), "--headless", "--ram-expansion-kb", "11",
                "--prg", str(sys_prg), "--prg-sys", "--esp-at-tcp",
                "--script", str(session_path),
            ], cwd=EMU, text=True, capture_output=True, timeout=300)
            emulator_log_path.write_text(result.stdout + result.stderr)
        finally:
            stop_group(server)

    server_text = server_log_path.read_text()
    captured = sorted(frames.glob("frame-*.png"))
    if result.returncode:
        raise SystemExit(f"emulator failed; see {emulator_log_path}")
    if "Game finished" not in server_text:
        raise SystemExit(f"game did not finish; see {server_log_path}")
    if "Client error" in server_text:
        raise SystemExit(f"server rejected a client action; see {server_log_path}")
    if len(captured) != expected_frames:
        raise SystemExit(f"expected {expected_frames} frames, captured {len(captured)}")
    shutil.copyfile(captured[-1], poster_path)
    encode_video(frames, video_path)
    if video_path.stat().st_size < 10_000:
        raise SystemExit("encoded video is unexpectedly small")
    duration = expected_frames / VIDEO_FPS
    print(f"Captured {expected_frames} frames ({duration:.1f}s): {video_path}")
    print(f"Poster: {poster_path}")


if __name__ == "__main__":
    try:
        main()
    except subprocess.TimeoutExpired as error:
        print(f"timed out: {error}", file=sys.stderr)
        raise SystemExit(1)
