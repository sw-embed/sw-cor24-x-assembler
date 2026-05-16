# Saga: lgo-compact-flag

## Goal

Add `--lgo-full` / `--lgo-compact` flag pair to `cor24-asm`. Default
is `--lgo-full` (today's bit-identical behavior; hardware-safe
everywhere). `--lgo-compact` opt-in: skip pure-zero `L` records;
loadable in `cor24-emu` and on FPGA cold boot, not safe on warm
reload.

Brief: /disk1/github/softwarewrighter/devgroup/tools/briefs/dcxas-lgo-compact-flag.md

## Why default Full

- Conservative — bit-identical to today's output; no caller regresses.
- Hardware-safe by default — once FPGA arrives, full output is the
  right thing without needing a flag.
- Opt-in compaction is documented at the call site (build pipelines
  that target `cor24-emu` opt in explicitly).

## What's actually changing

| File | Change |
|---|---|
| `src/lgo.rs` | add `pub enum LgoMode { Full, Compact }`; thread through `write(..., mode, ...)`; in Compact mode, skip chunks where every byte is `0x00` |
| `cli/src/main.rs` | add `--lgo-full` and `--lgo-compact` flags (mutually exclusive); store in `Cli.lgo_mode`; pass to `lgo::write`; update `USAGE` |
| `src/lgo.rs` (tests) | unit tests: Compact strips pure-zero chunks; Compact preserves non-zero chunks byte-identically; Compact preserves `G` record; Full default unchanged |
| `cli/tests/cli.rs` | CLI integration: default = Full bit-identical; `--lgo-compact` strips zero lines; mutex error; non-zero L lines preserved |
| `tests/integration_tests.rs` | round-trip: assemble fixture both modes, load each via `load_lgo`, verify CPU bytes equivalent at non-zero positions (semantic safety check from brief test #6) |
| `README.md` | add the two flags to the CLI example block |

## Architectural note

Mutex check fires at parse time (both flags present → exit 2 with
clear error mentioning both names). When neither flag is given,
default is Full — i.e., the implicit choice matches today's behavior.

`G` records and `;` comments are unaffected — always emitted in both
modes per the brief's format constraints.

## Out of scope (per brief)

- No `.lgo` format changes (no new record types, no syntax extensions).
- No `cor24-emu` changes (already handles sparse addresses).
- No automatic build-pipeline flip (each consuming repo decides
  whether to pass `--lgo-compact`).
- No changes to `bin-to-lgo.sh` in sw-cor24-snobol4.

## Steps

1. **implement-lgo-compact-flag** — single step. Add `LgoMode`,
   thread through emitter, CLI flag pair, mutex check, tests, README
   update. Full workspace verify.

(Single step — change is small, tightly coupled, and well-specified.)

## When done

`dg-mark-pr` to rename `feat/lgo-compact-flag` → `pr/lgo-compact-flag`,
then commit post-complete bookkeeping on a separate branch and rename
to `pr/lgo-compact-flag-saga-complete` so mike can relay both.
