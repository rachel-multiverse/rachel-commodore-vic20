# PAL and NTSC serial timing

The VIC-20 client bit-bangs 8N1 serial over user-port CB2 (TX) and PB0 (RX).
The external ESP-AT modem begins at 9600 baud and is changed to 2400 baud before
continuous RUBP traffic.

## Automatic detection

At startup, before serial traffic and while interrupts are disabled, the client
observes one wrap of VIC-I raster register `$9004`. This register exposes
scanline divided by two: a 312-line PAL frame reaches about 155, while a
261-line NTSC frame reaches about 130. A maximum of 140 or greater selects PAL;
otherwise the client selects NTSC. Detection does not depend on the KERNAL
jiffy clock.

## Delay tables

| Path | PAL loop count | NTSC loop count |
|---|---:|---:|
| 9600 TX | 13 | 11 |
| 9600 RX full bit | 16 | 14 |
| 9600 RX half bit | 7 | 6 |
| 2400 TX | 82 | 75 |
| 2400 RX full bit | 85 | 78 |
| 2400 RX half bit | 45 | 41 |

The counts include calibration against the fixed instructions surrounding each
delay loop. Emu198x models the PAL CPU at 1,108,405 Hz and NTSC at 1,022,727 Hz;
its external modem bridge therefore uses 115 and 107 CPU cycles respectively
for a nominal 9600-baud bit and tracks the negotiated 2400-baud rate.

## Verification

`make e2e-full-game` and `make e2e-full-game-ntsc` each complete a deterministic
match through the real Go server, including modem setup, HELLO/WELCOME, deal,
actions, CRC-valid state traffic and the terminal game event. Physical support
still requires the corresponding full match on real PAL and NTSC units.
