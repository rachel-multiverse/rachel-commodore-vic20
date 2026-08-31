# VIC-20 assembly conventions

Rachel is a single ca65 translation unit assembled from a small include graph.
`src/main.asm` is the root; `src/solo.asm` is the root of the offline game.
Splitting a module does not create a linker boundary, so forward references and
the generated program remain unchanged.

## Solo module map

| File | Responsibility |
|---|---|
| `solo/ui.asm` | memory contract, kernel descriptor and offline front end |
| `solo/api.asm` | AI policy, action count and persistent-state API |
| `solo/actions.asm` | indexed action decoding and state transitions |
| `solo/deck.asm` | card encoding, packed deck, hands, shuffle and PRNG |
| `solo/rules.asm` | legality queries, turn rules and private storage |
| `solo/fixtures.asm` | code and data assembled only with `SOLO_KERNEL_TEST` |

The include order in `src/solo.asm` is deliberate. Keep data near its owning
module, but remember that labels remain visible across the whole translation
unit. A new dependency between modules should be a call to a named routine or
a documented shared field, not a branch to another module's private label.

## Routine contract

The 6502 has no hardware calling convention, so public entry points document:

- input registers, flags, pointers and required buffer sizes;
- output registers or flags;
- clobbered registers, zero-page locations and shared temporaries.

`A`, `X`, `Y` and processor flags are caller-saved unless a routine explicitly
says otherwise. `ZP_PTR1`, `ZP_PTR2`, `ZP_PTR3` and `ZP_TEMP1`–`ZP_TEMP4` are
shared scratch. A caller must not expect them to survive a `jsr`. Private local
labels inherit the contract of their entry routine.

Carry is used for fallible kernel operations: clear means success and set means
invalid input or rejection. Count/query functions state their result register
explicitly rather than relying on incidental flags.

## Memory ownership

Solo play and online play are mutually exclusive. The 80-byte solo workspace
overlays the first 80 bytes of the contiguous RUBP transmit/receive buffers;
its 16-byte scratch area occupies the next bytes in the receive buffer. Compile-
time assertions in `solo/ui.asm` make that relationship fail at assembly time if
the protocol buffers or compact state layout move.

Variables below the routines in `solo/rules.asm` are private storage, not an
external ABI. The offsets beginning with `SW_` and the save/info formats are
contracts and require fixture and documentation updates when changed.

## Labels and control flow

Exported or cross-module routines use descriptive `solo_` names. Short prefixes
such as `sgaa_` are private labels belonging to the nearest routine. Prefer a
forward branch to a private label for local control flow and `jsr` for reusable
behaviour. Do not jump into another routine's interior.

Comments should explain representation, invariants, hardware constraints or a
non-obvious choice. They are free in the assembled program, but stale comments
are defects: update them with the code they describe.

## Verification

`make test` assembles with ca65, runs protocol/kernel checks, checks the memory
budget and enforces structural assembly rules. A source-only split should leave
the release PRG byte-identical. The optional `make asm198x-check` exercises the
same recursive include graph through Asm198x and emits its symbol and Debug198x
artifacts; it is a compatibility check, while ca65/ld65 remains the release
toolchain and byte-level oracle.
