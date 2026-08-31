# Solo play feasibility and memory budget

## Decision

Proceed with one PRG for the first playable solo slice. The current production
image leaves enough measured CODE space for a compact two-player kernel while
retaining a hard 2 KiB contingency. A disk menu with separate online and solo
programs remains a packaging fallback, not the current design.

This is a feasibility result, not yet a claim that solo play is implemented.
The checked-in spike proves the workspace lifetime, canonical fixture import
shape, linker budget and executable fixture loader.

## Measured baseline

The 8K expansion exposes `$1200-$3FFF`; CODE occupies `$1210-$3FFF`:

| Item | Bytes |
|---|---:|
| Linker CODE capacity | 11,760 |
| Current production CODE payload | 6,156 |
| Current unused CODE | 5,604 |
| Required contingency | 2,048 |
| First-playable CODE ceiling | 9,712 |
| Remaining first-slice implementation allowance | 3,556 |

`tests/check_memory_budget.py` reads the fresh ld65 map, emits
`build/memory-budget.json`, and fails once production CODE crosses 9,712 bytes.
CI retains the JSON as an artifact.

The current production PRG is 6,173 bytes including its load address, BASIC
trampoline and padding. The test-only fixture harness is 6,514 bytes; its
fixture and validation code are excluded from production.

## Resident ownership and lifetime

Solo mode uses the frozen `constrained_2p_v2` RachelWorkspace profile:

| Storage | Bytes | Binding |
|---|---:|---|
| Resident workspace | 80 | `tx_buffer` through the first 16 bytes of `rx_buffer` |
| Transient scratch | 16 | `rx_buffer+16` through `rx_buffer+31` |
| Remaining overlaid receive bytes | 32 | available for indexed action/apply results |
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

- `NEW_GAME` — deterministic two-player deal and initial discard
- `GET_ACTION_COUNT` — count legal draw/play choices without an action table
- `GET_ACTION_AT` — inspect one canonical action, up to 16 bytes
- `APPLY_ACTION` — mutate the compact workspace and return the bounded summary

`LIST_ACTIONS` is deliberately excluded: its 806-byte table would erase useful
contingency for no gameplay benefit. `SAVE_STATE`/`LOAD_STATE` are deferred
until the playable slice proves its real code size. Their external RKSI image
may reuse transport storage only while offline.

The deterministic opponent iterates indexed legal actions and chooses the first
play action, otherwise draw. Ace suit selection counts the remaining hand by
suit. It does not implement its own legality rules.

The first rules-core checkpoint now implements `GET_ACTION_COUNT` and
`GET_ACTION_AT` directly over hand masks. Portable action order is canonical by
card identity, including Ace nomination expansion and multi-card stacks, so it
does not depend on a host language's array order. Forced draws, draw/skip
counter rules and nominated-suit legality share the same enumerator.

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

The indexed-action checkpoint consumed 559 of the 1,600-byte legality/action
ceiling. Its executable catalogue tests are intentionally exhaustive rather
than timing representative; the playable UI will cache a count and request
only the selected indexed action.

## Executable fixture evidence

`tests/fixtures/kernel-state-v1.hex` is the canonical RKSI fixture from
RachelEngine. `tests/solo_kernel.py` checks its ABI/spec versions and state
fields and checks the compact fixture binding. `make solo-kernel-spike` builds a
test-only PRG whose 6502 loader copies exactly 80 bytes into the real overlay
and validates key fields.

Emu198x executed that PRG with 8K expansion and read `$A5` from the exported
result byte, proving the loader, overlay and indexed catalogue execute rather
than merely assemble. `make solo-kernel-e2e` parses the current linker label dynamically,
runs the harness and checks the byte, so later code movement cannot stale the
test address.

## Go/no-go and disk fallback

Continue with a single PRG while all of these remain true:

- production CODE is no larger than 9,712 bytes
- resident workspace remains 80 bytes plus 16 scratch
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
