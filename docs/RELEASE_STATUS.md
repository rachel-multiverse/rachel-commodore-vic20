# VIC-20 release status

## Current classification

This build is an **emulator-verified PAL/NTSC release candidate**. It is feature
complete for two-to-eight-seat solo play and online RUBP play in one 8K-expanded
PRG. It must remain labelled experimental on physical hardware until the
checklist in `HARDWARE_TESTING.md` is completed on a real unit.

## Verified without physical hardware

- Production and test PRGs assemble under cc65 in GitHub Actions.
- Protocol, CRC, state recovery, action encoding and memory ceilings are checked
  on every push.
- The compact 6502 kernel has executable catalogue, apply, draw, shuffle,
  recycle, persistence, invalid-mutation and GET_INFO fixtures.
- A cycle-accurate Emu198x soak exercises 16 seeds with a 1,024-turn bound per
  seed and exports progress, bounded outcomes and failure reason. The seeds
  cycle every table size from two to eight seats, so directional turn order,
  stepping over seats that have gone out, the per-count deal and finish
  counting are all covered rather than only the two-player case. Every turn of
  every game asserts that the 52 cards are conserved across hands, deck and
  discard pile. No seed now reaches the turn bound.
- A complete solo game reaches a winner without a server, at every table size.
- A complete online game reaches the terminal server event through Emu198x's
  cycle-driven user-port ESP-AT bridge and the real Go server.
- The online *human* input path is driven separately against the same server
  with the production PRG rather than the autoplay build, confirming that the
  Ace suit prompt appears at the moment of play, that the cursor keys change
  the nomination, and that confirming carries through to the sent play.
- Automatic raster-based region detection selects separate PAL and NTSC
  software-UART timing tables.
- Complete online games pass under both PAL and NTSC Emu198x timing models.
- The title-to-solo game screen is visually captured under PAL emulation.
- The release ZIP contains the PRG, controls, status and hardware checklist and
  has a SHA-256 sidecar.

ROM licensing prevents the emulator run itself from executing on the hosted
runner, so CI assembles its executable fixture while the ROM-backed run remains
a reproducible local release check (`make solo-kernel-e2e`).

## Persistence decision

The rules core already provides deterministic 125-byte `RKS2` save/load with a
checksum, structural validation and byte-identical round-trip tests. The release
candidate does **not** expose disk save/resume in its UI.

Doing so safely requires choosing and testing a real storage path (datasette,
1541-compatible disk, SD2IEC/Ultimate device, or an online-hosted save). KERNAL
I/O also temporarily owns memory and interrupts that the screen and software
UART depend upon. With only 15 bytes remaining before the conservative
feature ceiling, an untestable storage implementation would spend contingency
and create a misleading compatibility claim. The stable RKS2 format means this
can be added later without changing saved game semantics.

## Remaining release blockers

- Complete the physical checklist on PAL and NTSC VIC-20s with 8K expansion.
- Verify the real user-port modem/adapter electrical and serial path.
- Complete the physical checklist separately on an NTSC VIC-20 before calling
  its now emulator-calibrated network timing hardware-supported.

Everything else is release polish rather than a known gameplay blocker.

## Corrections carried by this candidate

Three defects found while implementing issue #10, listed because two of them
had been shipping and neither was visible to the source-level checks:

- `solo_deck_pop` shifted one byte past the 39-byte packed deck, which is
  `SW_DISCARD_COUNT`. Every draw zeroed the discard count, so the pile could
  never be recycled and the deepest deck slots took its bits. Two-player games
  rarely drained the deck far enough to show it; three of sixteen soak seeds
  were silently grinding to the turn bound because of it, and now none do.
- `render_hand` discarded the page base it had just computed, so once the hand
  passed five cards the selected card scrolled off the row entirely.
- Solo play seeded every game, and every replay, with the fixture's constant
  42, so the deal never varied.
