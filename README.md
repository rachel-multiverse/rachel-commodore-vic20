# Rachel VIC-20 Client

A VIC-20 client for the Rachel card game, written in 6502 assembly.

## Requirements

- **Hardware**: VIC-20 with 8KB+ memory expansion
- **Networking**: ESP8266/ESP32 WiFi modem connected to user port
- **Assembler**: cc65 toolchain (ca65, ld65)

## Building

```bash
make clean
make
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
| RETURN | Play selected cards |
| D | Draw card |
| RUN/STOP | Quit game |

## Memory Map

With 8KB expansion:
- `$1000-$11FF`: Screen RAM (22×23 chars)
- `$1201-$3FFF`: Program code and data (~11.5KB available)

## Hardware Connection

The WiFi modem connects to the VIC-20 user port:
- PA7: TX (output)
- PA6: RX (input)
- GND: Ground

Uses AT commands for ESP8266/ESP32 modems.

## Platform ID

VIC-20 = `0x000C` (12)

## Protocol

Uses RUBP (Rachel Universal Binary Protocol) - 64-byte fixed messages.
See `docs/PROTOCOL.md` for specification.

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
