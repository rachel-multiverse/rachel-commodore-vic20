# VIC-20 physical test checklist

## Required setup

- A PAL or NTSC VIC-20 with at least 8KB RAM expansion
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
2. Confirm the title offers `S SOLO` and `O ONLINE`, centred and legible.
3. Choose Solo, play with keyboard and joystick through a complete match,
   including an Ace nomination and a legal draw. Confirm win/loss and `R`
   replay, then use `O` to return to the mode menu.
4. Choose Online and confirm the IP and optional room-code prompts. Join both a
   public lobby (blank room code) and a private lobby.
5. Interrupt the network during an active game. Verify automatic reconnection,
   the same player number and hand, then complete the match. Also verify the
   manual retry/quit prompt by keeping the server unavailable for three tries.
6. Play online using keyboard, then joystick: move, select, nominate an Ace suit,
   play and draw. Check that held directions do not repeat uncontrollably.
7. Confirm each short sound cue without missed network messages.
8. Complete a two-player game and verify finish position, spectator state,
   final card-holder and turn count.
9. Join an eight-player match and verify all player counts and the current
   player remain readable throughout.
10. Power-cycle and repeat one complete match from a fresh load.

Record VIC model/revision, PAL/NTSC, RAM expansion, modem firmware, adapter,
server commit, PRG checksum and any observed failure. Both timing sets complete
emulated matches, but each video standard must remain experimentally labelled
until a complete network match passes on corresponding physical hardware.
