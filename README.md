# Rachel VIC-20 Client

A VIC-20 client for the Rachel card game, written in 6502 assembly.

## Requirements

- **Hardware**: VIC-20 with 8KB+ memory expansion
- **Video standard**: PAL for network play (the software UART is cycle-tuned)
- **Networking**: ESP8266/ESP32 WiFi modem connected to user port
- **Assembler**: cc65 toolchain (ca65, ld65)

## Building

```bash
make clean
make
make test
```

This produces `build/rachel.prg`.

`make release` creates a distributable ZIP and SHA-256 checksum under
`build/release/`, containing the production PRG, instructions and physical
hardware test checklist.

## Running

Load the program in a VIC-20 emulator (VICE xvic) with 8KB expansion:

```bash
xvic -memory 8k build/rachel.prg
```

Then type `RUN` to start.

## Controls

| Key | Action |
|-----|--------|
| ← → | Move cursor |
| SPACE | Select/deselect card |
| ↑ ↓ | Choose suit for an ace |
| RETURN | Play selected cards |
| D | Draw card |
| RUN/STOP | Quit game |

## Memory Map

With 8KB expansion:
- `$1000-$11FF`: Screen RAM (22×23 chars)
- `$1201-$3FFF`: Program code and data (~11.5KB available)

## Hardware Connection

The WiFi modem connects to the VIC-20 user port:
- User-port pin M / VIA CB2: TX (output)
- User-port pin C / VIA PB0: RX (input)
- GND: Ground

Uses ESP-AT commands for ESP8266/ESP32 modems. This pin mapping targets the
real Sven Petersen C64 WiFi modem with the
documented VIC-20 edge adapter. The driver waits for the ESP-AT `CIPSEND`
prompt before transmitting and strips `+IPD`/status text by
synchronising received data on the RUBP `RACH` magic.

Do not connect a bare 3.3V ESP module directly to 5V logic or power. Use the
documented modem/edge-adapter combination or suitable regulation and level
translation. See `docs/HARDWARE_TESTING.md` before trying physical hardware.

PAL is the supported physical network target. The display/game code is not
region-specific, but the bit-banged serial timings have not been calibrated on
an NTSC unit; NTSC network play is therefore experimental rather than a release
claim.

## Platform ID

VIC-20 = `0x000C` (12)

## Protocol

Uses canonical RUBP v2 (Rachel Unified Binary Protocol) 64-byte messages,
including the `WELCOME`, private `GAME_START`/`CARD_DRAWN`/`HAND_SYNC`, and
public `GAME_STATE` flows. Action messages carry RachelSpec v1 metadata.
Every v2 frame carries a CRC-16/CCITT-FALSE checksum over the complete frame;
corrupt inbound frames are discarded and every outbound frame is finalised
immediately before transmission. The ESP-AT link is reduced to 2400 baud before
TCP traffic so the VIC-20 software UART can reliably receive continuous frames.
Full specification: [rachel-multiverse/protocol](https://github.com/rachel-multiverse/protocol).

GitHub Actions builds the PRG and verifies its BASIC `RUN` trampoline, memory
layout, canonical fixture shape, recovery metadata and action encoding on every
change.

Emu198x accepts the PRG, selects the 8KB expansion and executes the BASIC `SYS`
trampoline. Its cycle-driven PB0/CB2 ESP-AT bridge has completed an end-to-end
game turn against the real Go server: HELLO/lobby admission, initial deal,
authoritative state recovery, keyboard `D`, accepted DRAW_CARD, CARD_DRAWN,
turn advancement, and rendering the resulting eight-card hand. The reproducible
input sequence is in `tests/emu198x_draw_e2e.json`; run the Go server locally
with one AI opponent and pass that script to Emu198x's VIC-20 runner.

GitHub Actions also compiles a test-only one-card autoplay PRG. Production PRGs
contain no autoplay code. A complete emulator/server run remains a local test
because VIC-20 ROM images cannot be redistributed to hosted runners.

To run that complete deterministic game, build Emu198x's release VIC-20 runner,
set `EMU198X_DIR` to its checkout, and run `make e2e-full-game`. The adjacent
Go server checkout is used by default; override it with `RACHEL_SERVER_DIR`.
Logs and the final screenshot are retained under `build/e2e-output/`. The test
requires the server to finish and rejects any run containing a client error.
`make e2e-eight-player` runs the same production path with seven AI opponents
and retains its independent evidence under `build/e2e-output-8/`.
`make e2e-reconnect` uses a TCP proxy to sever an active match, requires the Go
server to report that the original player was reclaimed, and then completes
the game. It uses 300 ms host frame spacing, slightly above the approximately
267 ms needed to receive a complete 64-byte frame at 2400 baud.

For a reproducible presentation recording of the same authentic emulator run,
install `ffmpeg` and run `make capture-video` with `EMU198X_DIR` set. This saves
sampled emulator frames, logs, the replayable session, a poster image and an
H.264 MP4 under `build/video-capture/`. The default is a roughly 44-second,
4x nearest-neighbour recording; `RACHEL_CAPTURE_EVERY`, `RACHEL_CAPTURE_FPS`
and `RACHEL_CAPTURE_SCALE` can tune its pacing and output size.

The checksum lets the VIC-20 safely retain the server's authoritative state hash
and include it with play, draw and recovery requests. The server can therefore
reject actions based on stale state instead of relying on syntax alone.

## Screen Layout

The VIC-20's 22×23 character display is used as:
- Line 0: Turn indicator
- Lines 2-7: PETSCII discard card
- Lines 8-11: Public card counts for all eight seats
- Lines 14-16: Turn state and controls
- Lines 18-22: Player's hand

Keyboard and joystick are both supported. Left/right moves through the hand;
Space or Fire selects a card; up/down chooses the Ace suit. Fire+up plays the
selection and Fire+down draws. Short, non-blocking VIC sound cues acknowledge
movement, selection, actions, errors and the final result.

If an established TCP link closes, the client retains its opaque session token
and assigned game ID, reconnects automatically, reclaims the same seat and
requests an authoritative public/private state refresh. Three automatic tries
are followed by a manual retry-or-quit prompt.

## Files

- `src/main.asm` - Entry point and main loop
- `src/equates.asm` - Constants and memory addresses
- `src/display.asm` - Screen output routines
- `src/input.asm` - Keyboard handling
- `src/rubp.asm` - RUBP protocol implementation
- `src/game.asm` - Game rendering
- `src/connect.asm` - Connection handling
- `src/net/wifi.asm` - WiFi modem driver
