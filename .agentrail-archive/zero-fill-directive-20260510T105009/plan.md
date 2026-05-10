# Saga: zero-fill-directive

## Goal

Add `.zero N` directive to `cor24-asm` that emits N zero bytes at the
current location counter. Pure source-density fix: replaces the
`.byte 0,0,...,0` enumeration that bloats SNOBOL4's `sno_main.s` to
~261 KB (~97.7% zero-fill text). Output bytes unchanged.

Brief: /disk1/github/softwarewrighter/devgroup/tools/briefs/dcxas-zero-fill-directive.md

Pairs with: `dcpls-emit-zero-fill.md` (PL/SW codegen change that
consumes this directive). dcxas lands first; dcpls follows.

## Spelling

`.zero N` — matches GNU as; matches dcpls's default expectation per
the partner brief. No spelling deviation; no extra docs needed for
the choice.

## What's actually changing

| File | Change |
|---|---|
| `src/assembler.rs:222` | new arm in `handle_directive` for `.zero`; emits N zero bytes, advances address |
| `src/assembler.rs` (tests) | unit tests: produces N zeros, `N=0` no-op, byte-identity vs `.byte 0,...,0`, works in `.data`, works in `.text` |
| `tests/integration_tests.rs` | CLI/round-trip smoke test with mixed `.zero` and non-zero data; verify `.lgo` and `--listing` |

## Architectural note

`.text`/`.data` are no-ops in this assembler's flat memory model,
so `.zero` works in both segments without restriction. It emits
real bytes — no `.bss` semantics, no loader change. Output `.bin`
and `.lgo` are byte-identical to today's spelled-out form.

Today, `.zero` falls through the catch-all `_ => {}` arm in
`handle_directive`, so `.zero 1024` is silently a no-op. After this
change it emits 1024 zero bytes.

## Out of scope (per brief)

- No `.bss` / segment / loader-side machinery.
- No expression evaluation for N (constant only is fine for v1).
- No changes to `.byte`, `.word`, or any other existing directive.
- No PL/SW changes (partner brief).

## Steps

1. **implement-zero-directive** — single step; ~20 lines of code.
   Add the directive arm; add unit + integration tests; full
   workspace verify (`cargo build --workspace --release && cargo
   test --workspace && cargo clippy --workspace --all-targets
   --all-features -- -D warnings && target/release/cor24-asm -V`).
   Commit. complete --done. dg-mark-pr.

(Single step — the change is small and tightly coupled; one commit.)

## When done

`dg-mark-pr` to rename `feat/zero-fill-directive` →
`pr/zero-fill-directive`. Mike relays via `dg-relay dcxas
sw-cor24-x-assembler pr/zero-fill-directive` and reinstalls
`cor24-asm` to `work/bin/`. Then dcpls's partner saga unblocks.
