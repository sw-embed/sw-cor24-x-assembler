# Saga: makerlisp-button-echo

## Goal

Add `src/examples/assembler/button_echo_makerlisp.s` — a 27-byte
byte-identical reproduction of MakerLisp's canonical `blinky_s2`
demo — and wire it into the existing `tests/integration_tests.rs`
fixture list.

Brief: /disk1/github/softwarewrighter/devgroup/tools/briefs/dcxas-makerlisp-button-echo.md
Patch: /disk1/github/softwarewrighter/devgroup/tools/briefs/0001-feat-examples-add-Button-Echo-MakerLisp-variant.patch

## Why a brief instead of dwxas-direct PR

dwxas authored + tested the change in their sibling clone, but per
the primary-repo-only convention only dcxas's clone goes to mike's
relay. Brief hands off via format-patch to preserve dwxas's
authorship.

## What's actually changing (per patch)

| File | Change |
|---|---|
| `src/examples/assembler/button_echo_makerlisp.s` (new, 36 lines) | the reconstructed source for blinky_s2 |
| `tests/integration_tests.rs` (2 hunks) | register `("Button Echo (MakerLisp)", ...)` in `examples()`; add to `non_halting` array in `test_all_examples_halt` |

No public API change. No `Cargo.toml` change. No new dependencies.

## Architectural note

Source order in `button_echo_makerlisp.s` is load-bearing: the
loop body must assemble to exactly 14 bytes so the `start:` block
lands at offset `0x000E`. The patch's source preserves this by
keeping `loop:` first and `start:` after.

Verified-byte-identical L record (per brief):
`L000000807F7E652B0000FF2E00820013F82900ECFE662A00E0FEC7000000`.

## Out of scope

- No `G` record emission (this assembler's CLI doesn't yet emit one;
  upstream blinky_s2.lgo carries `G00000E` but byte payload matches).
- No changes to `button_echo.s` (the original variant stays).
- No emulator changes.

## Steps

1. **apply-makerlisp-button-echo-patch** — single step. Apply the
   format-patch via `git am` (preserves dwxas authorship), run
   `cargo test --workspace` + clippy, verify the new fixture is in
   the `examples()` list and assembles. Two commits on the branch:
   the agentrail saga setup (dcxas), then dwxas's `git am` commit.

(Single step — change is small and well-specified by the patch.)

## When done

Two pr/ branches per the established pattern:
- `pr/makerlisp-button-echo` — the work (saga setup + dwxas's commit)
- `pr/makerlisp-button-echo-saga-complete` — post-complete bookkeeping

Per the brief's cleanup section, dwxas will delete their stale
sibling-clone branch after mike relays.
