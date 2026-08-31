#!/usr/bin/env python3
"""Create the small, reproducible VIC-20 release bundle."""

from hashlib import sha256
from pathlib import Path
import shutil
import subprocess
import zipfile


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build" / "release"
PRG = ROOT / "build" / "rachel.prg"


def main() -> None:
    if not PRG.is_file():
        raise SystemExit("build/rachel.prg is missing; run make first")
    revision = subprocess.run(
        ["git", "describe", "--always", "--dirty"], cwd=ROOT,
        check=True, text=True, capture_output=True,
    ).stdout.strip()
    OUT.mkdir(parents=True, exist_ok=True)
    archive = OUT / f"rachel-vic20-{revision}.zip"
    staged_name = "rachel-vic20.prg"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as bundle:
        bundle.write(PRG, staged_name)
        bundle.write(ROOT / "README.md", "README.md")
        bundle.write(ROOT / "docs/HARDWARE_TESTING.md", "HARDWARE_TESTING.md")
        bundle.write(ROOT / "docs/RELEASE_STATUS.md", "RELEASE_STATUS.md")
    digest = sha256(archive.read_bytes()).hexdigest()
    checksum = archive.with_suffix(archive.suffix + ".sha256")
    checksum.write_text(f"{digest}  {archive.name}\n")
    print(archive.relative_to(ROOT))
    print(checksum.relative_to(ROOT))


if __name__ == "__main__":
    main()
