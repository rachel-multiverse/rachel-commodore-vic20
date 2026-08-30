# Rachel VIC-20 Client

A VIC-20 client for the Rachel card game, written in 6502 assembly.

## Requirements

- **Hardware**: VIC-20 with 8KB+ memory expansion
- **Video standard**: PAL (the current 9600-baud loop is cycle-tuned for PAL)
- **Networking**: ESP8266/ESP32 WiFi modem connected to user port
- **Assembler**: cc65 toolchain (ca65, ld65)

## Building

```bash
make clean
make
make test
```

This produces `build/rachel.prg`.

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

## Platform ID

VIC-20 = `0x000C` (12)

## Protocol

Uses canonical RUBP v1 (Rachel Unified Binary Protocol) 64-byte messages,
including the `WELCOME`, private `GAME_START`/`CARD_DRAWN`/`HAND_SYNC`, and
public `GAME_STATE` flows. Action messages carry RachelSpec v1 metadata.
Full specification: [rachel-multiverse/protocol](https://github.com/rachel-multiverse/protocol).

GitHub Actions builds the PRG and verifies its BASIC `RUN` trampoline, memory
layout, canonical fixture shape, recovery metadata and action encoding on every
change.

VICE 3.10 recognises and injects the generated PRG with an 8KB expansion, but a
bounded automated run still remains visibly at the BASIC prompt. Emu198x also
accepts the PRG and selects the expansion, but its queued `RUN` has the same
observable result. Executable validation is therefore still pending; the
Emu198x path is tracked in
[emu198x/emu198x#1304](https://github.com/emu198x/emu198x/issues/1304).

## Screen Layout

The VIC-20's 22×23 character display is used as:
- Line 0: Turn indicator
- Lines 3-5: Discard pile / game info
- Lines 18-22: Player's hand

## Files

- `src/main.asm` - Entry point and main loop
- `src/equates.asm` - Constants and memory addresses
- `src/display.asm` - Screen output routines
- `src/input.asm` - Keyboard handling
- `src/rubp.asm` - RUBP protocol implementation
- `src/game.asm` - Game rendering
- `src/connect.asm` - Connection handling
- `src/net/wifi.asm` - WiFi modem driver
