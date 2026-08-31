# VIC-20 release status

## Current classification

This build is an **emulator-verified PAL release candidate**. It is feature
complete for two-player solo play and online RUBP play in one 8K-expanded PRG.
It must remain labelled experimental on physical hardware until the checklist
in `HARDWARE_TESTING.md` is completed on a real unit.

## Verified without physical hardware

- Production and test PRGs assemble under cc65 in GitHub Actions.
- Protocol, CRC, state recovery, action encoding and memory ceilings are checked
  on every push.
- The compact 6502 kernel has executable catalogue, apply, draw, shuffle,
  recycle, persistence, invalid-mutation and GET_INFO fixtures.
- A cycle-accurate Emu198x soak exercises 16 seeds with a 1,024-turn bound per
  seed and exports progress, bounded outcomes and failure reason.
- A complete solo game reaches a winner without a server.
- A complete online game reaches the terminal server event through Emu198x's
  cycle-driven user-port ESP-AT bridge and the real Go server.
- The title-to-solo game screen is visually captured under PAL emulation.
- The release ZIP contains the PRG, controls, status and hardware checklist and
  has a SHA-256 sidecar.

ROM licensing prevents the emulator run itself from executing on the hosted
runner, so CI assembles its executable fixture while the ROM-backed run remains
a reproducible local release check (`make solo-kernel-e2e`).

## Persistence decision

The rules core already provides deterministic 87-byte `RKS2` save/load with a
checksum, structural validation and byte-identical round-trip tests. The release
candidate does **not** expose disk save/resume in its UI.

Doing so safely requires choosing and testing a real storage path (datasette,
1541-compatible disk, SD2IEC/Ultimate device, or an online-hosted save). KERNAL
I/O also temporarily owns memory and interrupts that the screen and software
UART depend upon. With only 1,037 bytes remaining before the conservative
feature ceiling, an untestable storage implementation would spend contingency
and create a misleading compatibility claim. The stable RKS2 format means this
can be added later without changing saved game semantics.

## Remaining release blockers

- Complete the physical checklist on a PAL VIC-20 with an 8K expansion.
- Verify the real user-port modem/adapter electrical and serial path.
- Treat NTSC networking as experimental until its software-UART timing is
  calibrated and a complete real-hardware match succeeds.

Everything else is release polish rather than a known gameplay blocker.
