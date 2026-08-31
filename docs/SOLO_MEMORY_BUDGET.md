# Solo play feasibility and memory budget

## Decision

Proceed with one PRG for the first playable solo slice. The current production
image leaves enough measured CODE space for a compact solo kernel while
retaining a hard 2 KiB contingency. A disk menu with separate online and solo
programs remains a packaging fallback, not the current design.

Solo play is now implemented in the same production PRG as online play. The
title selects either mode, the existing renderer exposes the full hand, and
human input is accepted only by matching an indexed legal kernel action.

## Measured baseline

The 8K expansion exposes `$1200-$3FFF`; CODE occupies `$1210-$3FFF`:

| Item | Bytes |
|---|---:|
| Linker CODE capacity | 11,760 |
| Current production CODE payload | 9,426 |
| Current unused CODE | 2,334 |
| Required contingency | 2,048 |
| First-playable CODE ceiling | 9,712 |
| Remaining first-slice implementation allowance | 286 |

Issue #10 spent 947 bytes on 31 August 2026 — the visible game-state work
(pending attacks, playability, the nomination prompt, hand paging, direction),
the move from two seats to eight, and the block-graphic title banner — taking
the allowance from 962 to 15. Reclaiming the published kernel API returned 274
of them and clearing the lobby text on the way into a game spent 3, so the line
stands at 286 with the 2,048-byte contingency untouched.

`SAVE_STATE`, `LOAD_STATE`, `GET_INFO` and the action-count entry point are
compiled into the fixture build and left out of the production PRG. Nothing on
a VIC-20 can call them: there is no external consumer for a descriptor or a
save image on this machine, and the front end drives `solo_apply_action`
directly. The fixtures still exercise every one of them, so conformance is
unaffected; exposing save/resume in the UI later means moving one `.ifdef`
rather than rewriting anything.

The title banner is drawn from the character ROM's half-block glyphs rather
than a redefined character set. That is not only a size choice. The VIC can
fetch glyphs from RAM below `$2000` or the ROM at `$8000`, and every
1K-aligned RAM slot below `$2000` is inside CODE, so a custom set would mean
splitting the CODE segment around an aligned hole and costing a further 512 to
1,024 bytes. Worth revisiting only if CODE is ever restructured for another
reason.

`tests/check_memory_budget.py` reads the fresh ld65 map, emits
`build/memory-budget.json`, and fails once production CODE crosses 9,712 bytes.
CI retains the JSON as an artifact.

The current production PRG is 9,714 bytes including its load address, BASIC
trampoline and padding. The test-only fixture harness adds executable catalogue,
rejection, play and packed-deck draw assertions; its
fixture and validation code are excluded from production.

## Resident ownership and lifetime

Solo mode uses the `constrained_8p_v3` RachelWorkspace profile, which succeeded
the two-seat `constrained_2p_v2` when the table grew to eight
(docs/knowledge/decisions/0006-vintage-clients-may-ship-a-solo-kernel.md):

| Storage | Bytes | Binding |
|---|---:|---|
| Resident workspace | 118 | `tx_buffer` through `rx_buffer+53` |
| Spare overlaid receive bytes | 10 | `rx_buffer+54` through `rx_buffer+63` |
| Transient scratch | 16 | its own storage, outside both RUBP frames |
| Zero page | 0 additional resident bytes | existing `ZP_TEMP*`/pointer temporaries only |

This overlay is legal only because online transport and offline solo execution
are mutually exclusive lifetimes. Entering solo mode must not initialize or
call RUBP/network code after the workspace becomes live. Returning to online
mode requires a full mode reset and fresh `rubp_init`.

Screen RAM remains `$1000-$11FF`. The hardware stack remains `$0100-$01FF`.
The longest current application call paths use fewer than 24 stack bytes;
solo implementation reserves a 96-byte combined application/KERNAL-IRQ budget
and forbids recursion. The 16-byte kernel scratch area is not allocated on the
6502 stack.

## First playable command subset

The first slice implements the semantic equivalents of:

- `NEW_GAME` — deterministic deal for two to eight seats, and initial discard
- `GET_ACTION_COUNT` — count legal draw/play choices without an action table
- `GET_ACTION_AT` — inspect one canonical action, up to 16 bytes
- `APPLY_ACTION` — mutate the compact workspace and return the bounded summary

`LIST_ACTIONS` is deliberately excluded: its 806-byte table would erase useful
contingency for no gameplay benefit. `SAVE_STATE`/`LOAD_STATE` are implemented
for the compact in-memory format, but production disk I/O is deferred as
described in `RELEASE_STATUS.md`.

The deterministic opponent consumes indexed legal actions and does not
implement its own legality rules.

The shipped first policy is the documented budget fallback: select canonical
action zero. Because the kernel orders every legal play before DRAW, this is
deterministically “first legal play, otherwise draw”; Ace action expansion makes
hearts the deterministic first nomination. The complete production policy is
15 bytes and delegates both legality and mutation to the indexed kernel.

The first rules-core checkpoint now implements `GET_ACTION_COUNT` and
`GET_ACTION_AT` directly over hand masks. Portable action order is canonical by
card identity, including Ace nomination expansion and multi-card stacks, so it
does not depend on a host language's array order. Forced draws, draw/skip
counter rules and nominated-suit legality share the same enumerator.

`APPLY_ACTION` now validates an indexed action before the first workspace
write, then applies canonical card order, nomination, draw/skip attacks, red
and black Jacks, reversals, finish marking and directional turn advancement
past players who have gone out.
Packed-deck draws execute directly on the 6-bit stream. The same packed area
stores the live deck followed by buried discards, preserving chronological
discard order without another buffer. Exhaustion shuffles that exact trailing
sequence with the canonical PRNG and retains the current top card.

`NEW_GAME` implements canonical xorshift64, modulo reduction and Fisher-Yates
over the packed deck. The executable seed-42 vector matches both hands, the top
discard, first remaining card and final 64-bit RNG state from RachelEngine.

`SAVE_STATE` and `LOAD_STATE` use a deterministic 125-byte `RKS2` image: magic,
format version, payload length, the exact 118-byte workspace and checksum. Load
validates the complete image and structural bounds before its first workspace
write. This compact persistence format is intentionally distinct from RKSI,
whose general host representation does not describe the packed deck/discard
boundary needed by this profile.

## Planned first-slice code budget

| Component | Ceiling |
|---|---:|
| Mode menu and reset boundary | 160 bytes |
| Workspace helpers and card packing | 400 bytes |
| Deck, xorshift64, shuffle and deal | 900 bytes |
| Indexed legality and action application | 1,600 bytes |
| Deterministic AI policy | 250 bytes |
| Existing-display solo adapter and terminal flow | 700 bytes |
| Total | 4,010 bytes |

That plan finishes at 9,607 CODE bytes, leaving 2,153 bytes. Each stage is
measured from the linker map rather than trusted from this estimate.

The indexed-action and application checkpoints have consumed 1,174 of the
1,600-byte legality/action ceiling. Their executable catalogue tests are intentionally exhaustive rather
than timing representative; the playable UI will cache a count and request
only the selected indexed action.

The packed PRNG, shuffle, deal and exact discard recycling consumed 876 of
their 900-byte ceiling. Compact persistence adds 216 bytes outside the original
first-playable estimate. The remaining planned mode, AI and UI ceilings total
1,110 bytes, leaving 739 bytes of additional headroom before the separately
protected 2 KiB contingency.

The deterministic opponent consumed 15 of its 250-byte ceiling. The remaining
mode/reset and existing-display UI ceilings total 860 bytes, leaving 974 bytes
of implementation headroom before the protected contingency.

## Executable fixture evidence

`tests/fixtures/kernel-state-v1.hex` is the canonical RKSI fixture from
RachelEngine. `tests/solo_kernel.py` checks its ABI/spec versions and state
fields and checks the compact fixture binding. `make solo-kernel-spike` builds a
test-only PRG whose 6502 loader copies exactly 118 bytes into the real overlay
and validates key fields.

Emu198x executed that PRG with 8K expansion and read `$A5` from the exported
result byte, proving the loader, overlay and indexed catalogue execute rather
than merely assemble. `make solo-kernel-e2e` parses the current linker label dynamically,
runs the harness and checks the byte, so later code movement cannot stale the
test address.

The executable harness now exercises 16 deterministic seeds, each with a hard
1,024-turn bound. It exports games exercised, bounded outcomes and a precise
failure code. A legal game that reaches the bound is reported separately—the
finite deck can be recycled indefinitely—while missing/rejected actions,
invalid winners and state-transition failures fail the run.

## Go/no-go and disk fallback

Continue with a single PRG while all of these remain true:

- production CODE is no larger than 9,712 bytes
- resident workspace remains 118 bytes plus 16 scratch
- no full action table is allocated
- online/full-match tests remain unchanged and green
- canonical fixtures agree with indexed legality and application results

Stop and discuss disk packaging if the playable slice breaches the ceiling,
needs persistent online and solo buffers simultaneously, or cannot retain at
least 2 KiB for fixes and save/load. The preferred fallback is one disk image
containing a small selection program plus `RACHEL ONLINE` and `RACHEL SOLO`
PRGs. It is preferable to an opaque overlay loader: users can select a mode,
each executable remains independently testable, and loose PRGs can still be
distributed for SD2IEC/Ultimate/emulator users.
