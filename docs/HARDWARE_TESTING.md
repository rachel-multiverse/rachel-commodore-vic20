# VIC-20 physical test checklist

## Required setup

- A PAL VIC-20 with at least 8KB RAM expansion
- A Sven Petersen-style C64 WiFi modem and its documented VIC-20 user-port
  edge adapter, or an electrically equivalent ESP-AT interface
- A server reachable on TCP port 6502
- `rachel-vic20.prg` from the release archive

Never attach a bare 3.3V ESP8266/ESP32 directly to the VIC-20's 5V signals or
power rail. Confirm regulation, level compatibility, connector orientation and
common ground before switching on. The client uses user-port M/CB2 for TX and
C/PB0 for RX.

## Release acceptance

1. Load the PRG with the 8KB expansion enabled and enter `RUN`.
2. Confirm the title, IP prompt and optional room-code prompt are centred and
   legible, with no wrap or stale characters.
3. Join both a public lobby (blank room code) and a private lobby.
4. Interrupt the network during an active game. Verify automatic reconnection,
   the same player number and hand, then complete the match. Also verify the
   manual retry/quit prompt by keeping the server unavailable for three tries.
5. Play using keyboard, then joystick: move, select, nominate an Ace suit,
   play and draw. Check that held directions do not repeat uncontrollably.
6. Confirm each short sound cue without missed network messages.
7. Complete a two-player game and verify finish position, spectator state,
   final card-holder and turn count.
8. Join an eight-player match and verify all player counts and the current
   player remain readable throughout.
9. Power-cycle and repeat one complete match from a fresh load.

Record VIC model/revision, PAL/NTSC, RAM expansion, modem firmware, adapter,
server commit, PRG checksum and any observed failure. NTSC serial operation is
currently experimental and must not be marked supported without a complete
network match on real NTSC hardware.
