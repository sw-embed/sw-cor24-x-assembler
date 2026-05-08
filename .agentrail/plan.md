# Saga: depend-on-isa-not-emulator

## Goal

Drop `cor24-emulator` from `sw-cor24-x-assembler`'s compile-time
deps. Replace it with a direct path-dep on `cor24-isa` (the new
small foundational crate, extracted from the emulator by dcemu's
`pr/extract-isa`). The emulator stays as a `dev-dependency` for the
`.lgo` round-trip tests in `src/lgo.rs` and the
runtime-execution tests in `src/assembler.rs`.

Brief: /disk1/github/softwarewrighter/devgroup/tools/briefs/dcxas-depend-on-isa-not-emulator.md

## What's actually changing

| File | Change |
|---|---|
| `Cargo.toml` | move `cor24-emulator` to `[dev-dependencies]`; add `cor24-isa = { path = "../sw-cor24-isa" }` to `[dependencies]` |
| `src/lib.rs` | remove `pub use cor24_emulator;` (anti-pattern re-export) |
| `src/assembler.rs:6-7` | swap `cor24_emulator::cpu::encode` → `cor24_isa::encode`; `cor24_emulator::cpu::instruction::Opcode` → `cor24_isa::Opcode` |
| `src/assembler.rs` (tests) | imports at `:1154, :1225` and use at `:1180` are inside `#[test]` fns (`test_led_blink_integration`, `test_branch_loop_integration`); they use runtime types (`CpuState`, `Executor`, `ExecuteResult`) that legitimately stay in the emulator — leave as-is, they resolve via dev-deps |
| `src/lgo.rs:45-46` | inside `#[cfg(test)] mod tests` — leave as-is |
| `cli/Cargo.toml` | unchanged (only depends on the parent lib) |
| `README.md` | drop mention of `sw-cor24-emulator` from the `## Dependencies` section; mention `sw-cor24-isa` instead |

## Architectural note

Production users of `cor24-asm` (binary or library) only need a
sibling clone of `sw-cor24-isa`. Test execution still requires
`sw-cor24-emulator`. Future cleanup (out of scope) could inline a
stub `.lgo` parser in the test crate to fully sever the dev-dep,
but that's a separate saga.

## Steps (planned)

1. **drop-emulator-dep** — Cargo.toml refactor; remove `pub use
   cor24_emulator;` from `src/lib.rs`; switch the two non-test
   imports in `src/assembler.rs` from `cor24_emulator::cpu::*` to
   `cor24_isa::*`. README dependencies section update. Full
   workspace verify (`cargo build --workspace --release && cargo
   test --workspace && cargo clippy --workspace --all-targets
   --all-features -- -D warnings && target/release/cor24-asm -V`).
   Commit. complete --done. dg-mark-pr.

(Single step — the change is mechanical and tightly coupled; one
commit.)

## Out of scope

- No emulator changes (separate repo).
- No isa repo changes (separate repo).
- No new functionality.
- No drop of cor24-emulator from `dev-dependencies` (round-trip
  tests need it).

## When done

`dg-mark-pr` to rename `feat/depend-on-isa-not-emulator` →
`pr/depend-on-isa-not-emulator`. Mike relays via `dg-relay dcxas
sw-cor24-x-assembler pr/depend-on-isa-not-emulator`.
